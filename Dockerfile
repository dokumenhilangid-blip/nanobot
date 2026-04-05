FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

# Install Node.js 20 for the WhatsApp bridge
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates gnupg git openssh-client && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get purge -y gnupg && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies first (cached layer)
COPY pyproject.toml README.md LICENSE ./
RUN mkdir -p nanobot bridge && touch nanobot/__init__.py && \
    uv pip install --system --no-cache . && \
    rm -rf nanobot bridge

# Copy the full source and install
COPY nanobot/ nanobot/
COPY bridge/ bridge/
RUN uv pip install --system --no-cache .

# Build the WhatsApp bridge
WORKDIR /app/bridge
RUN git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/ && \
    git config --global --add url."https://github.com/".insteadOf git@github.com: && \
    npm install && npm run build
WORKDIR /app

# Create config directory
RUN mkdir -p /root/.nanobot

# Gateway default port
EXPOSE 18790

ENTRYPOINT ["/bin/bash","-c"]
# Gunakan shell form supaya variabel environment ($) terbaca
CMD sh -c "python3 -c \"import json, os; \
home = os.path.expanduser('~/.nanobot'); \
os.makedirs(home, exist_ok=True); \
config = { \
    'channels': { \
        'telegram': { \
            'enabled': True, \
            'token': os.getenv('TELEGRAM_TOKEN'), \
            'allowFrom': [], \
            'groupPolicy': 'mention' \
        } \
    }, \
    'agent': { \
        'provider': 'openrouter', \
        'model': os.getenv('MODEL'), \
        'apiKey': os.getenv('OPENROUTER_API_KEY') \
    } \
}; \
with open(os.path.join(home, 'config.json'), 'w') as f: \
    json.dump(config, f)\" && python3 -m nanobot gateway"
