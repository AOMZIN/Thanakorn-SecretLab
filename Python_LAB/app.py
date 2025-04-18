from flask import Flask, render_template, request, jsonify
import pandas as pd
import numpy as np
import os
import yfinance as yf
from datetime import datetime

app = Flask(__name__)
app.config['DATA_FOLDER'] = 'data'

# Create data folder if it doesn't exist
os.makedirs(app.config['DATA_FOLDER'], exist_ok=True)

def get_historical_data(ticker, start_date, end_date):
    """Download historical data for ticker using yfinance"""
    try:
        # Try to download from Yahoo Finance
        data = yf.download(ticker, start=start_date, end=end_date)
        if len(data) > 0:
            # Save to CSV for caching
            filename = f"{app.config['DATA_FOLDER']}/{ticker}_historical.csv"
            data.to_csv(filename)
            return data

        # If download failed, try to use cached data if available
        filename = f"{app.config['DATA_FOLDER']}/{ticker}_historical.csv"
        if os.path.exists(filename):
            return pd.read_csv(filename, index_col=0, parse_dates=True)

        return None
    except Exception as e:
        print(f"Error downloading {ticker}: {str(e)}")
        return None

def calculate_returns(df):
    """Calculate monthly returns from price data"""
    # Convert index to datetime if it's not already
    if not isinstance(df.index, pd.DatetimeIndex):
        df.index = pd.to_datetime(df.index)

    # Calculate monthly returns
    monthly_returns = df['Close'].resample('M').last().pct_change().dropna()
    return monthly_returns

def calculate_portfolio_metrics(tickers, allocations, start_date, end_date):
    """Calculate portfolio metrics from historical data"""
    # Validate inputs
    if len(tickers) != len(allocations) or sum(allocations) != 100:
        return {"error": "Invalid allocations. Must sum to 100%"}

    # Convert allocations to decimal
    weights = [a/100 for a in allocations]

    # Get historical data for each ticker
    ticker_data = {}
    for ticker in tickers:
        data = get_historical_data(ticker, start_date, end_date)
        if data is None:
            return {"error": f"Could not get data for {ticker}"}
        ticker_data[ticker] = data

    # Calculate monthly returns for each ticker
    all_returns = {}
    for ticker, data in ticker_data.items():
        all_returns[ticker] = calculate_returns(data)

    # Align all return series on the same dates before creating DataFrame
    aligned_returns = []
    for ticker in tickers:
        aligned_returns.append(all_returns[ticker])

    returns_df = pd.concat(aligned_returns, axis=1, keys=tickers)

    # Handle different date ranges by taking the intersection
    returns_df = returns_df.dropna()

    if len(returns_df) == 0:
        return {"error": "No overlapping data periods found"}

    # Calculate portfolio returns
    portfolio_returns = returns_df.dot(weights)

    # Calculate metrics
    metrics = {}

    # Basic return metrics
    metrics['Arithmetic Mean (monthly)'] = portfolio_returns.mean()
    metrics['Arithmetic Mean (annual)'] = (1 + metrics['Arithmetic Mean (monthly)'])**12 - 1
    metrics['Geometric Mean (monthly)'] = (1 + portfolio_returns).prod()**(1/len(portfolio_returns)) - 1
    metrics['Geometric Mean (annual)'] = (1 + metrics['Geometric Mean (monthly)'])**12 - 1

    # Risk metrics
    metrics['Standard Deviation (monthly)'] = portfolio_returns.std()
    metrics['Standard Deviation (annual)'] = metrics['Standard Deviation (monthly)'] * np.sqrt(12)

    # Drawdown analysis
    cumulative_returns = (1 + portfolio_returns).cumprod()
    running_max = cumulative_returns.cummax()
    drawdowns = (cumulative_returns / running_max) - 1
    metrics['Maximum Drawdown'] = drawdowns.min()

    # Performance ratios
    metrics['Sharpe Ratio'] = metrics['Arithmetic Mean (annual)'] / metrics['Standard Deviation (annual)']

    # Correlation matrix
    metrics['Correlation Matrix'] = returns_df.corr().to_dict()

    return metrics

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/analyze', methods=['POST'])
def analyze_portfolio():
    try:
        data = request.json
        tickers = data.get('tickers', [])
        allocations = data.get('allocations', [])
        start_year = data.get('startYear', '2006')
        start_month = data.get('startMonth', 'Jan')
        end_year = data.get('endYear', '2025')
        end_month = data.get('endMonth', 'Dec')

        # Convert month names to numbers
        month_map = {'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04', 'May': '05', 'Jun': '06',
                     'Jul': '07', 'Aug': '08', 'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'}

        start_date = f"{start_year}-{month_map[start_month]}-01"
        end_date = f"{end_year}-{month_map[end_month]}-28"

        metrics = calculate_portfolio_metrics(tickers, allocations, start_date, end_date)
        return jsonify(metrics)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True)
