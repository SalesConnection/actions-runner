FROM summerwind/actions-runner:ubuntu-22.04

# Install SSH
RUN sudo apt-get -yq update && \
    sudo apt-get -yq install ssh && \
    sudo rm -rf /var/lib/apt/lists/*
