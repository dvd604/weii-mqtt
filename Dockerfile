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

# Install pipx and upgrade base tools
RUN python3 -m pip install --upgrade pip setuptools wheel pipx \
    && python3 -m pipx ensurepath

# Install weii via pipx (puts binary on PATH)
RUN pipx install weii

# Add pipx binaries to PATH for runtime
ENV PATH=/root/.local/bin:$PATH

# --- Install Python dependencies for Garmin ---
RUN pip install garminconnect

WORKDIR /app

# Copy scripts into container
COPY weigh_loop.sh .
COPY garmin_weight_sync.py .

# Create directory for Garmin session cache
RUN mkdir -p /app/session

# Make scripts executable
RUN chmod +x weigh_loop.sh garmin_weight_sync.py

# Persist session.json in this directory
VOLUME ["/app/session"]

CMD ["./weigh_loop.sh"]
