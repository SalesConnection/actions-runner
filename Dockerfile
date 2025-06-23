FROM summerwind/actions-runner:ubuntu-22.04

# Install SSH
RUN apt-get update -yq && \
    apt-get install -yq ssh && \
    rm -rf /var/lib/apt/lists/*
