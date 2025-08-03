log.file.path.set("/var/logs/liquidsoap/liquidsoap.log")
settings.init.allow_root.set(true)
settings.harbor.bind_addrs := ["0.0.0.0"]

settings.server.timeout.set(100.)
settings.log.stdout.set(true)
settings.log.level.set(3)
settings.log.file.append.set(false)

server.telnet()
enable_replaygain_metadata()

listeners_count = ref(0)
last_metadata = ref([])
min_download_id = ref(0)
request_queue = request.queue()
logging_prefix = "********************"

playing_enabled = interactive.bool("playing_enabled", bool_of_string(environment.get("LS_AUTOPLAY")))
base_download_url = environment.get("BASE_DOWNLOAD_URL")
icecast_mount = environment.get("ICECAST_MOUNT")
icecast_password = environment.get("ICECAST_SOURCE_PASSWORD")


######################################################################################################################
### Radio definition
######################################################################################################################

def on_track(m)
    if list.length(m) > 0 then
        last_metadata := m
        download_id = m["jukebox_download_id"]
        callback_url = m["jukebox_started_playing_url"]
        title = m["title"]
        artist = m["artist"]
        log("#{logging_prefix} Started playing download id: #{download_id}, #{title}, #{artist}")
        url = "#{base_download_url}#{callback_url}"
        h = http.post(url)
        if h.status_code != 200 then
            log.important("#{logging_prefix} Call to #{url} failed")
            log.important("#{logging_prefix} Status code: #{h.status_code}, Message: #{h.status_message}")
        end
    end
end


def on_end(t, m)
    download_id = m["jukebox_download_id"]
    callback_url = m["jukebox_finished_playing_url"]
    title = m["title"]
    artist = m["artist"]
    log("#{logging_prefix} Finished playing download id: #{download_id}, #{title}, #{artist}")
    url = "#{base_download_url}#{callback_url}"
    h = http.post(url)
    if h.status_code != 200 then
        log.important("#{logging_prefix} Call to #{url} failed")
        log.important("#{logging_prefix} Status code: #{h.status_code}, Message: #{h.status_message}")
    end
end


request_queue.on_track(on_track)
s2 = source.on_end(request_queue, on_end, delay=0.1)
#s2 = skipper(every=15., s2)
radio = switch(track_sensitive=false, [(playing_enabled, s2), ({true}, blank())])


id = %ffmpeg(format="mp3", %audio(codec="libmp3lame", q=7))

output.icecast(
    id,
    radio,
    mount=icecast_mount,
    host="icecast", 
    port=8000, 
    password=icecast_password)
    

######################################################################################################################
### API Definition
######################################################################################################################

def convert_metadata_to_json(m)

    def get_or_default(key, default)
        if list.exists(fun (x) -> fst(x) == key, m) then
            m[key]
        else
            default
        end
    end

    album = get_or_default("album", "")
    artist = get_or_default("artist", "")
    title = get_or_default("title", "")
    download_id = get_or_default("jukebox_download_id", "0")
    download_id = int_of_string(download_id)
    j = json()
    j.add("album", album)
    j.add("artist", artist)
    j.add("title", title)
    j.add("playbackId", download_id)
    json.stringify(j)
end


def append_to_queue(request, response)
    try
        let json.parse ({downloadId, downloadUrl} : {downloadId: int, downloadUrl: string}) = request.body()
        let url = "#{base_download_url}#{downloadUrl}"
        request_queue.push.uri(url)
        log("#{logging_prefix} Appended #{downloadId} to the request queue")
        response.status_code(200)
    catch err: [error.json] do
        response.status_code(400)
        response.data("#{err.message}")
    end
end


def replace_queue(request, response)
    try
        let json.parse ({downloadId, downloadUrl} : {downloadId: int, downloadUrl: string}) = request.body()
        let url = "#{base_download_url}#{downloadUrl}"
        request_queue.set_queue([])
        request_queue.push.uri(url)
        log("#{logging_prefix} Set request queue to #{downloadId}")
        response.status_code(200)
    catch err: [error.json] do
        response.status_code(400)
        response.data("#{err.message}")
    end
end


def get_queue(_, response)

    def get_metadata(req) =
        meta = request.metadata(req)
        convert_metadata_to_json(meta)
    end

    q = request_queue.queue()
    json_list = list.map(get_metadata, q)
    json_list = string.concat(json_list, separator=",")
    json_list = "[#{json_list}]"

    response.status_code(200)
    response.content_type("application/json")
    response.data(json_list)
end


def clear_queue(_, response)
    request_queue.set_queue([])
    log("#{logging_prefix} Cleared the request queue")
    response.status_code(200)
end


def get_current_track(_, response)
    m = last_metadata()
    data = convert_metadata_to_json(m)

    response.status_code(200)
    response.content_type("application/json")
    response.data(data)
end


def delete_current_track(request, response)
    last_metadata := []
    radio.skip()
    response.status_code(200)
end


def replace_playing_enabled(request, response)
    try
        let json.parse ({playingEnabled} : {playingEnabled: bool}) = request.body()
        playing_enabled.set(playingEnabled)
        response.status_code(200)
    catch err: [error.json] do
        response.status_code(400)
        response.data("#{err.message}")
    end
end


def get_playing_enabled(request, response)
    j = json()
    j.add("playingEnabled", playing_enabled())
    data = json.stringify(j)
    response.headers([("content-type", "application/json")])
    response.status_code(200)
    response.data(data)
end


def get_health(request, response)
    j = json()
    j.add("healthy", true)
    data = json.stringify(j)
    response.headers([("content-type", "application/json")])
    response.status_code(200)
    response.data(data)
end


harbor.http.register(port=8080, method="GET", "/request_queue", get_queue)
harbor.http.register(port=8080, method="POST", "/request_queue", append_to_queue)
harbor.http.register(port=8080, method="PUT", "/request_queue", replace_queue)
harbor.http.register(port=8080, method="DELETE", "/request_queue", clear_queue)

harbor.http.register(port=8080, method="GET", "/current_track", get_current_track)
harbor.http.register(port=8080, method="DELETE", "/current_track", delete_current_track)

harbor.http.register(port=8080, method="GET", "/playing_enabled", get_playing_enabled)
harbor.http.register(port=8080, method="PUT", "/playing_enabled", replace_playing_enabled)

harbor.http.register(port=8080, method="GET", "/health", get_health)
