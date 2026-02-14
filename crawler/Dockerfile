# Use lightweight Python image
FROM python:3.9-slim

WORKDIR /app

# Copy requirements.txt and install dependencies
COPY requirements.txt .

# Install dependencies
# Use '--no-cache-dir' to reduce image size
RUN pip install --no-cache-dir -r requirements.txt

# Copy the main script to the container
COPY main.py .

# Set the entrypoint to the main script
CMD ["python", "main.py"]