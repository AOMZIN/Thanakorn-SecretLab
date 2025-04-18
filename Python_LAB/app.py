from flask import Flask, render_template, request, jsonify
import pandas as pd
import numpy as np
import os
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['ALLOWED_EXTENSIONS'] = {'csv'}

# Create uploads folder if it doesn't exist
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in app.config['ALLOWED_EXTENSIONS']

def calculate_metrics(df):
    """Calculate portfolio metrics from CSV data"""
    # This is where you'll implement the calculations for all your metrics
    # For this example, I'll implement a few basic ones
    
    metrics = {}
    
    # Example calculations (you'll need to adjust these based on your actual CSV structure)
    # Assuming monthly returns are in a column called 'Returns'
    if 'Returns' in df.columns:
        returns = df['Returns'].dropna()
        
        # Calculate basic metrics
        metrics['Arithmetic Mean (monthly)'] = returns.mean()
        metrics['Arithmetic Mean (annualized)'] = (1 + returns.mean())**12 - 1
        metrics['Geometric Mean (monthly)'] = (1 + returns).prod()**(1/len(returns)) - 1
        metrics['Geometric Mean (annualized)'] = (1 + metrics['Geometric Mean (monthly)'])**12 - 1
        metrics['Standard Deviation (monthly)'] = returns.std()
        metrics['Standard Deviation (annualized)'] = returns.std() * np.sqrt(12)
        
        # Calculate drawdowns
        cumulative_returns = (1 + returns).cumprod()
        running_max = cumulative_returns.cummax()
        drawdowns = (cumulative_returns / running_max) - 1
        metrics['Maximum Drawdown'] = drawdowns.min()
        
        # Calculate Sharpe ratio (assuming risk-free rate = 0 for simplicity)
        metrics['Sharpe Ratio'] = metrics['Arithmetic Mean (annualized)'] / metrics['Standard Deviation (annualized)']
        
        # Many more metrics would be calculated here...
    
    return metrics

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    
    file = request.files['file']
    
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
    
    if file and allowed_file(file.filename):
        filename = secure_filename(file.filename)
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        file.save(filepath)
        
        # Process the CSV file
        try:
            df = pd.read_csv(filepath)
            metrics = calculate_metrics(df)
            return jsonify({'metrics': metrics}), 200
        except Exception as e:
            return jsonify({'error': str(e)}), 500
    
    return jsonify({'error': 'File type not allowed'}), 400

if __name__ == '__main__':
    app.run(debug=True)