# ---- build stage -------------------------------------------------------
FROM python:3.14-slim AS build

WORKDIR /app
COPY requirements.txt .
# Install into an isolated prefix we can copy into the runtime image.
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- runtime stage -----------------------------------------------------
FROM python:3.14-slim AS runtime

# Version is injected at build time: docker build --build-arg VERSION=0.2.0
ARG VERSION=dev

# Run as a non-root user with a fixed UID, so Kubernetes can enforce
# runAsNonRoot and the policy gate can check it.
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app

COPY --from=build /install /usr/local
COPY main.py .

ENV APP_VERSION=${VERSION} \
    MOCK_LLM=true \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER 10001
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health').status==200 else 1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
