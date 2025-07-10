# Liquidsoap Radio

This is a small Liquidsoap implementation with the following properties:

* Expects a service to tell it which tracks to play. The service provides a URL pointing to the MP3. 
* Liquidsoap will download the track and call back to the provider when it starts playing and when it finishes playing. The callback URLs are currently hardcoded.
* It streams to Icecast so the Icecast mount name and password need to be provided.