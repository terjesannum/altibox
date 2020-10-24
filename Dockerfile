FROM perl:5.32.0

RUN cpan -i LWP::UserAgent \
        && cpan -i LWP::Protocol::https \
        && cpan -i JSON \
        && cpan -i Text::Table

ENV ALTIBOX_USER ""
ENV ALTIBOX_PASSWORD ""
ENV ALTIBOX_FORMAT ""
ENV ALTIBOX_OUTPUT ""
ENV ALTIBOX_VERBOSE 0

COPY altibox-devices.pl /

ENTRYPOINT [ "/altibox-devices.pl" ]
