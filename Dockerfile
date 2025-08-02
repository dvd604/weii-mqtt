FROM python:3.11-slim

# Install dependencies for weii and mosquitto_pub
RUN apt-get update && apt-get install -y \
    bluetooth \
    bluez \
    libbluetooth-dev \
    libudev-dev \
    build-essential \
    mosquitto-clients \
    && rm -rf /var/lib/apt/lists/*

# Install pipx to install weii isolated
RUN python3 -m pip install --upgrade pip setuptools wheel pipx
RUN python3 -m pipx ensurepath

# Install weii via pipx (puts binary on PATH)
RUN pipx install weii

# Add pipx binaries to PATH for runtime
ENV PATH=/root/.local/bin:$PATH

WORKDIR /app

# Copy your script into container
COPY weigh_loop.sh .

RUN chmod +x weigh_loop.sh

CMD ["./weigh_loop.sh"]
