# check=skip=SecretsUsedInArgOrEnv

# Description: Dockerfile for HSF Nginx with Certbot

FROM nginx:stable

LABEL org.opencontainers.image.title="HSF Nginx with Certbot"
LABEL org.opencontainers.image.description="Nginx Reverse Proxy with Certbot configured for serving the HSF WWW site"
LABEL org.opencontainers.image.authors="jonathan@hyrysoftwarefoundation.org"

EXPOSE 80/tcp
EXPOSE 443/tcp

ENV HSF_DOMAIN="hyrysoftwarefoundation.org"
ENV HSF_CONTACT="jonathan@hyrysoftwarefoundation.org"
ENV HSF_BACKEND_SERVER="71.9.242.212"
ENV HSF_BACKEND_PORT="8443"
ENV HSF_DUMMYCERT_EXPIRY="3650"

# This is not a secret... this is the key size for the RSA key used to generate
#  domain certificates through Let's Encrypt via certbot.
# Thus, the warning is ignored at the beginning of the file.
ENV HSF_RSA_KEY_SIZE="8192"

RUN apt-get update && \
    # Prepare for updating libxml2, krb5, and libheif to fix CVEs in the nginx stable image.
    apt-get install -y --no-install-recommends --no-install-suggests \
      git autoconf automake libtool libreadline8 zlib1g liblzma5 \
      libreadline-dev zlib1g-dev liblzma-dev libc6-dev pkg-config \
      python3 python3-dev make bison g++ libcmocka-dev libsocket-wrapper \
      libresolv-wrapper cmake libx265-dev libpng-dev libjpeg-dev \
      libde265-dev libaom-dev libdav1d-dev libgdk-pixbuf2.0-dev certbot \
      python3-certbot-nginx python3-pip && \
    dpkg -r --force-depends libxml2 libheif1 && \
    # Update libxml2 to 2.13.8 to fix a bunch of CVEs in the nginx stable image.
    git clone https://gitlab.gnome.org/GNOME/libxml2.git /tmp/libxml2 && \
    cd /tmp/libxml2 && \
    git checkout v2.13.8 && \
    ./autogen.sh && \
    MAKE='gmake' CFLAGS='-O2 -fno-semantic-interposition' ./configure && \
    make && make check && \
    make install && \
    ln -s /usr/local/lib/libxml2.so.2 /usr/lib/x86_64-linux-gnu/libxml2.so.2 && \
    cd /tmp && \
    rm -Rf libxml2 && \
    # Update krb5 to 1.21.3 to fix CVE-2025-3576 in the nginx stable image.
    git clone https://github.com/krb5/krb5.git && \
    cd /tmp/krb5 && \
    git checkout krb5-1.21.3-final && \
    cd /tmp/krb5/src && \
    autoreconf --verbose && \
    ./configure && \
    make && make check && \
    make install && \
    cd /tmp && \
    rm -Rf krb5 && \
    # Update libheif to 1.19.6 to fix multiple CVEs in the nginx stable image.
    git clone https://github.com/strukturag/libheif.git && \
    cd /tmp/libheif && \
    git checkout v1.19.6 && \
    mkdir -p /tmp/libheif/build && \
    cd /tmp/libheif/build && \
    cmake --preset=release .. && make && \
    cmake --install . && \
    cd /tmp && \
    rm -Rf libheif && \
    mkdir -p /etc/letsencrypt/live/${HSF_DOMAIN} && \
    openssl req -x509 -nodes -newkey rsa:${HSF_RSA_KEY_SIZE} \
      -days ${HSF_DUMMYCERT_EXPIRY} -subj '/CN=localhost' \
      -keyout /etc/letsencrypt/live/${HSF_DOMAIN}/privkey.pem \
      -out /etc/letsencrypt/live/${HSF_DOMAIN}/fullchain.pem && \
    dpkg --force-all -P git autoconf automake libtool libreadline-dev \
      zlib1g-dev liblzma-dev libc6-dev pkg-config python3-dev make \
      cmake libx265-dev libpng-dev libjpeg-dev libde265-dev \
      libaom-dev libdav1d-dev libgdk-pixbuf2.0-dev g++ bison \
      libcmocka-dev libresolv-wrapper libsocket-wrapper && \
    apt-get --dry-run autoremove | grep -Po 'Remv \K[^ ]+' | \
      xargs -r dpkg --force-all -P && \
    apt-get clean -y && \
    rm -Rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc && \
    # Install versions of certbot dependencies required to fix CVEs and GHSAs.
    pip3 install --break-system-packages cryptography==43.0.1 && \
    pip3 install --break-system-packages certifi==2024.7.4 && \
    pip3 install --break-system-packages urllib3==1.26.19 && \
    pip3 install --break-system-packages idna==3.7 && \
    pip3 install --break-system-packages requests==2.32.0 && \
    pip3 install --break-system-packages configobj==5.0.9 && \
    # Run the initial nginx process in the background
    echo -n " &" >> /docker-entrypoint.sh

# At this point, all low, medium, high, and critical CVEs in the nginx
#  stable image have now had fixes applied, and the image is ready for
#  the custom HSF configs, environment variables, ports, and other data.

COPY ./data/nginx/tmpl/hsf-site.conf.template /etc/nginx/conf.d/default.conf.template
COPY ./data/certbot/conf/options-ssl-nginx.conf /etc/letsencrypt/options-ssl-nginx.conf
COPY ./data/certbot/conf/ssl-dhparams.pem /etc/letsencrypt/ssl-dhparams.pem

COPY --chmod=500 ./run/entrypoint.sh /hsf-www-proxy.sh

ENTRYPOINT ["/hsf-www-proxy.sh"]

CMD ["nginx", "-g", "daemon off;"]
