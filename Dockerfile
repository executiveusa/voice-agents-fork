# voice-agents-fork (SYNTHIA — LiveKit Agents)
FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ make git \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast dependency management
RUN pip install --no-cache-dir uv

# Copy the workspace
COPY . .

# Install core agents package
RUN uv pip install --system -e ./livekit-agents

# Install common plugins
RUN uv pip install --system \
    -e ./livekit-plugins/livekit-plugins-openai \
    -e ./livekit-plugins/livekit-plugins-deepgram \
    -e ./livekit-plugins/livekit-plugins-elevenlabs \
    -e ./livekit-plugins/livekit-plugins-anthropic \
    -e ./livekit-plugins/livekit-plugins-google \
    -e ./livekit-plugins/livekit-plugins-cartesia \
    -e ./livekit-plugins/livekit-plugins-turn-detector

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import livekit.agents; print('ok')" || exit 1

# Default: run basic voice agent example
CMD ["python", "-m", "livekit.agents", "start", "--url", "${LIVEKIT_URL}", "examples/voice_agents/basic_agent.py"]
