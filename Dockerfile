# Multi-stage build for DocuSearch Backend
# Stage 1: Builder - Install Python dependencies
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies in a virtual environment
COPY requirements.txt .
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Stage 2: Production - Minimal runtime image
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for OCR and PDF processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-eng \
    tesseract-ocr-ben \
    tesseract-ocr-hin \
    poppler-utils \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Download Meetei Mayek (mni) trained data from tessdata repository
RUN curl -L https://github.com/tesseract-ocr/tessdata/raw/main/mni.traineddata \
    -o /usr/share/tesseract-ocr/5/tessdata/mni.traineddata

# Copy virtual environment from builder stage
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Set Tesseract data directory
ENV TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata

# Create non-root user for security
RUN useradd -m -u 1000 appuser && \
    mkdir -p /app/uploads /app/static /app/templates && \
    chown -R appuser:appuser /app

# Copy application files
COPY --chown=appuser:appuser main.py database.py ./
COPY --chown=appuser:appuser static/ ./static/
COPY --chown=appuser:appuser templates/ ./templates/

# Switch to non-root user
USER appuser

# Create volume mount point for persistent uploads
VOLUME ["/app/uploads"]

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8000/')" || exit 1

# Run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
