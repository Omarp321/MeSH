# Bruk en offisiell base image
FROM debian:bookworm

# Sett miljøvariabler for å unngå spørsmål under installasjon
ENV DEBIAN_FRONTEND=noninteractive

# Oppdater og installer nødvendige pakker, fjern cachefiler etter installasjon
RUN apt-get update && apt-get -y dist-upgrade && \
    apt-get install -y --no-install-recommends \
    sudo wget gnupg2 git-all g++ \
    libssl-dev libxml2-dev libboost-all-dev cmake make \
    apt-transport-https curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Installer Elasticsearch uten systemd, fjern unødvendige pakker etterpå
RUN wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add - && \
    echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list && \
    apt-get update && apt-get install -y elasticsearch && \
    rm -rf /var/lib/apt/lists/*

# Opprett en bruker for å kjøre Elasticsearch, hvis den ikke allerede finnes
RUN id -u elasticsearch &>/dev/null || useradd -m elasticsearch && \
    mkdir -p /var/lib/elasticsearch /var/log/elasticsearch && \
    chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

# Installer Wt og kompilere prosjektet, fjern nedlastet arkiv etter bruk

# Install Wt with the latest version and compile project
RUN mkdir -p /projects && cd /projects && \
    wget https://github.com/emweb/wt/archive/4.10.4.tar.gz && \
    tar -xvzf 4.10.4.tar.gz && \
    rm 4.10.4.tar.gz && \
    ln -s wt-4.10.4 wt && \
    cd wt && mkdir build && cd build && \
    cmake ../ -DENABLE_LIBWTDBO:BOOL=OFF && \
    make -j2 && \
    make install && ldconfig

# Klon prosjektet MeSH og cpp-elasticsearch
RUN git clone https://github.com/sigrunespelien/MeSH.git && \
    cd MeSH/MeSHImport && \
    git clone https://github.com/frodegill/cpp-elasticsearch.git && \
    cd ../MeSHWeb && \
    ln -sf ../MeSHImport/cpp-elasticsearch && \
    sudo mkdir -p /opt/Helsebib/MeSHWeb && \
    sudo ln -sf /usr/local/share/Wt/resources /opt/Helsebib/MeSHWeb

# Kopier nordesc2019.xml til MeSHImport-mappen (antatt at du har den lokalt)
COPY nordesc2019.xml /MeSH/MeSHImport/nordesc2019.xml

# Bygg prosjektet
WORKDIR /MeSH
RUN cd MeSHImport && \
    make clean && make -j2 && \
    cd ../MeSHWeb && \
    make clean && make -j2 && \
    sudo make install

# Bytt til ikke-root-bruker for Elasticsearch
USER elasticsearch

# Start Elasticsearch uten systemd og kjør importering og server
CMD /usr/share/elasticsearch/bin/elasticsearch -d && \
    sleep 60 && \
    cd MeSHImport && \
    ./MeSHImport localhost:9200 --clean --topnodes ./nordesc_topnodes.xml ./nordesc2019.xml && \
    cd ../MeSHWeb && \
    ./MeSHWeb --docroot . --config ./wt_config.xml --http-listen 0.0.0.0:8080