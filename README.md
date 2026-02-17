# Install tesseract
sudo apt-get update && sudo apt-get install -y tesseract-ocr tesseract-ocr-ben tesseract-ocr-hin

# Install dependencies
pip install -r requirements.txt

# Run the server
uvicorn main:app --port 8000 --reload