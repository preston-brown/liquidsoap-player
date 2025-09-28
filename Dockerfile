FROM savonet/liquidsoap:v2.4.0

COPY ./script.liq /etc/liquidsoap/script.liq

USER root
