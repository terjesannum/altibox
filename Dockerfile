FROM perl:5.32-slim

RUN apt-get update \
        && apt-get install -y --no-install-recommends openssl gcc libc6-dev libssl-dev libz-dev \
        && cpanm InfluxDB::LineProtocol \
        && cpanm JSON \
        && cpanm LWP::Protocol::https \
        && cpanm LWP::UserAgent \
        && cpanm Text::Table \
        && apt-get purge -y --auto-remove gcc libc6-dev libssl-dev libz-dev \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*

ENV ALTIBOX_USER ""
ENV ALTIBOX_PASSWORD ""
ENV ALTIBOX_FORMAT ""
ENV ALTIBOX_OUTPUT ""
ENV ALTIBOX_VERBOSE 0

COPY altibox-devices.pl /

ENTRYPOINT [ "/altibox-devices.pl" ]
