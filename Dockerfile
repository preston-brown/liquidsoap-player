FROM savonet/liquidsoap:v2.3.1

COPY ./script.liq /etc/liquidsoap/script.liq

USER root

