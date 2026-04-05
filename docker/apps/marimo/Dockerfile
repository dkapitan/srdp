# Use a standard Python image
FROM python:3.13-slim-bookworm

# Set the working directory inside the container
WORKDIR /app

# Copy the requirements file and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY app.py .

# Expose the port the app will run on
EXPOSE 8000

# Command to run the Marimo app
# --host 0.0.0.0 is crucial to make it accessible outside the container
CMD ["marimo", "run", "app.py", "--host", "0.0.0.0", "--port", "8000"]