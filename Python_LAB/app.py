# app.py
from flask import Flask, render_template, request, jsonify
import pandas as pd
import numpy as np
import os
import yfinance as yf
from datetime import datetime
from scipy.stats import norm, skew, kurtosis

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

def calculate_portfolio_metrics(tickers, allocations, start_date, end_date, benchmark_ticker=None):
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

    # Get benchmark data if provided
    benchmark_returns = None
    if benchmark_ticker:
        benchmark_data = get_historical_data(benchmark_ticker, start_date, end_date)
        if benchmark_data is not None:
            benchmark_returns = calculate_returns(benchmark_data)
            # Align with portfolio returns
            combined = pd.concat([portfolio_returns, benchmark_returns], axis=1)
            combined.columns = ['Portfolio', benchmark_ticker]
            combined = combined.dropna()
            if len(combined) > 0:
                portfolio_returns = combined['Portfolio']
                benchmark_returns = combined[benchmark_ticker]
            else:
                benchmark_returns = None

    # Calculate metrics
    metrics = {}
    
    # Assume annual risk-free rate of 2%
    risk_free_rate_annual = 0.02
    risk_free_rate_monthly = (1 + risk_free_rate_annual) ** (1/12) - 1

    # 1. Basic return metrics
    metrics['Arithmetic Mean (monthly)'] = portfolio_returns.mean()
    metrics['Arithmetic Mean (annual)'] = (1 + metrics['Arithmetic Mean (monthly)']) ** 12 - 1
    metrics['Geometric Mean (monthly)'] = (1 + portfolio_returns).prod() ** (1/len(portfolio_returns)) - 1
    metrics['Geometric Mean (annual)'] = (1 + metrics['Geometric Mean (monthly)']) ** 12 - 1

    # 2. Risk metrics
    metrics['Standard Deviation (monthly)'] = portfolio_returns.std()
    metrics['Standard Deviation (annual)'] = metrics['Standard Deviation (monthly)'] * np.sqrt(12)
    
    # 3. Downside risk metrics
    negative_returns = portfolio_returns[portfolio_returns < 0]
    metrics['Downside Deviation (monthly)'] = negative_returns.std() if len(negative_returns) > 0 else 0
    metrics['Downside Deviation (annual)'] = metrics['Downside Deviation (monthly)'] * np.sqrt(12)

    # 4. Drawdown analysis
    cumulative_returns = (1 + portfolio_returns).cumprod()
    running_max = cumulative_returns.cummax()
    drawdowns = (cumulative_returns / running_max) - 1
    metrics['Maximum Drawdown'] = drawdowns.min()
    
    # 5. Performance periods
    metrics['Best Month'] = portfolio_returns.max()
    metrics['Worst Month'] = portfolio_returns.min()
    
    # Calculate best/worst year
    annual_returns = portfolio_returns.groupby(pd.Grouper(freq='Y')).apply(
        lambda x: (1 + x).prod() - 1)
    if len(annual_returns) > 0:
        metrics['Best Year'] = annual_returns.max()
        metrics['Worst Year'] = annual_returns.min()
    
    # 6. Performance ratios
    excess_return_monthly = portfolio_returns.mean() - risk_free_rate_monthly
    excess_return_annual = metrics['Arithmetic Mean (annual)'] - risk_free_rate_annual
    
    # Sharpe ratio
    metrics['Sharpe Ratio (monthly)'] = excess_return_monthly / portfolio_returns.std() if portfolio_returns.std() > 0 else float('inf')
    metrics['Sharpe Ratio (annual)'] = excess_return_annual / metrics['Standard Deviation (annual)'] if metrics['Standard Deviation (annual)'] > 0 else float('inf')
    
    # Sortino ratio
    if metrics['Downside Deviation (monthly)'] > 0:
        metrics['Sortino Ratio (monthly)'] = excess_return_monthly / metrics['Downside Deviation (monthly)']
        metrics['Sortino Ratio (annual)'] = excess_return_annual / metrics['Downside Deviation (annual)']
    else:
        metrics['Sortino Ratio (monthly)'] = float('inf')
        metrics['Sortino Ratio (annual)'] = float('inf')
    
    # Calmar ratio
    if metrics['Maximum Drawdown'] != 0:
        metrics['Calmar Ratio'] = metrics['Arithmetic Mean (annual)'] / abs(metrics['Maximum Drawdown'])
    else:
        metrics['Calmar Ratio'] = float('inf')
    
    # 7. VaR metrics
    # Historical VaR (5%)
    metrics['Historical Value-at-Risk (5%)'] = np.percentile(portfolio_returns, 5)
    
    # Analytical VaR (5%) - assumes normal distribution
    z_score = norm.ppf(0.05)
    metrics['Analytical Value-at-Risk (5%)'] = portfolio_returns.mean() + z_score * portfolio_returns.std()
    
    # Conditional VaR / Expected Shortfall (5%)
    var_threshold = metrics['Historical Value-at-Risk (5%)']
    below_var = portfolio_returns[portfolio_returns <= var_threshold]
    metrics['Conditional Value-at-Risk (5%)'] = below_var.mean() if len(below_var) > 0 else float('nan')
    
    # 8. Distribution statistics
    metrics['Skewness'] = skew(portfolio_returns)
    metrics['Kurtosis'] = kurtosis(portfolio_returns) + 3  # Adding 3 for excess kurtosis to regular kurtosis
    
    # 9. Win/loss statistics
    positive_periods = (portfolio_returns > 0).sum()
    total_periods = len(portfolio_returns)
    metrics['Positive Periods'] = positive_periods
    metrics['Positive Periods (%)'] = (positive_periods / total_periods) * 100 if total_periods > 0 else 0
    
    avg_gain = portfolio_returns[portfolio_returns > 0].mean() if len(portfolio_returns[portfolio_returns > 0]) > 0 else 0
    avg_loss = abs(portfolio_returns[portfolio_returns < 0].mean()) if len(portfolio_returns[portfolio_returns < 0]) > 0 else 0
    
    if avg_loss > 0:
        metrics['Gain/Loss Ratio'] = avg_gain / avg_loss
    else:
        metrics['Gain/Loss Ratio'] = float('inf')
    
    # 10. Safe withdrawal rates (simple approximations)
    metrics['Safe Withdrawal Rate'] = max(0, metrics['Geometric Mean (annual)'] - 0.02)  # Conservative adjustment
    metrics['Perpetual Withdrawal Rate'] = max(0, metrics['Geometric Mean (annual)'] - 0.01)  # Even more conservative
    
    # 11. Benchmark-relative metrics (if benchmark provided)
    if benchmark_returns is not None:
        # Correlation with benchmark
        metrics['Benchmark Correlation'] = portfolio_returns.corr(benchmark_returns)
        
        # Beta calculation
        benchmark_variance = benchmark_returns.var()
        if benchmark_variance > 0:
            covariance = portfolio_returns.cov(benchmark_returns)
            metrics['Beta'] = covariance / benchmark_variance
        else:
            metrics['Beta'] = float('nan')
        
        # Alpha calculation (annualized)
        benchmark_mean_annual = (1 + benchmark_returns.mean()) ** 12 - 1
        if not np.isnan(metrics.get('Beta', float('nan'))):
            metrics['Alpha (annualized)'] = metrics['Arithmetic Mean (annual)'] - (
                risk_free_rate_annual + metrics['Beta'] * (benchmark_mean_annual - risk_free_rate_annual)
            )
        
        # R-squared
        metrics['R-squared'] = metrics['Benchmark Correlation'] ** 2
        
        # Treynor ratio
        if metrics.get('Beta', 0) != 0:
            metrics['Treynor Ratio (%)'] = (excess_return_annual / metrics['Beta']) * 100
        else:
            metrics['Treynor Ratio (%)'] = float('nan')
        
        # Tracking error
        tracking_diff = portfolio_returns - benchmark_returns
        metrics['Tracking Error (annual)'] = tracking_diff.std() * np.sqrt(12)
        
        # Information ratio
        active_return = metrics['Arithmetic Mean (annual)'] - benchmark_mean_annual
        metrics['Active Return (annual)'] = active_return
        if metrics['Tracking Error (annual)'] > 0:
            metrics['Information Ratio'] = active_return / metrics['Tracking Error (annual)']
        else:
            metrics['Information Ratio'] = float('nan')
        
        # Modigliani-Modigliani (M2) measure
        benchmark_std_annual = benchmark_returns.std() * np.sqrt(12)
        if benchmark_std_annual > 0:
            metrics['Modigliani-Modigliani (M2)'] = (
                metrics['Sharpe Ratio (annual)'] * benchmark_std_annual + risk_free_rate_annual
            )
        
        # Upside/Downside capture ratios
        up_market = benchmark_returns > 0
        down_market = benchmark_returns < 0
        
        if up_market.sum() > 0:
            portfolio_up = portfolio_returns[up_market].mean()
            benchmark_up = benchmark_returns[up_market].mean()
            if benchmark_up != 0:
                metrics['Upside Capture Ratio (%)'] = (portfolio_up / benchmark_up) * 100
        
        if down_market.sum() > 0:
            portfolio_down = portfolio_returns[down_market].mean()
            benchmark_down = benchmark_returns[down_market].mean()
            if benchmark_down != 0:
                metrics['Downside Capture Ratio (%)'] = (portfolio_down / benchmark_down) * 100
    
    # 12. Correlation matrix
    corr_matrix = returns_df.corr()
    metrics['Correlation Matrix'] = {
        str(ticker1): {str(ticker2): corr_matrix.loc[ticker1, ticker2] 
                      for ticker2 in corr_matrix.columns}
        for ticker1 in corr_matrix.index
    }

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
        benchmark_ticker = data.get('benchmarkTicker')

        # Convert month names to numbers
        month_map = {'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04', 'May': '05', 'Jun': '06',
                     'Jul': '07', 'Aug': '08', 'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'}

        start_date = f"{start_year}-{month_map[start_month]}-01"
        end_date = f"{end_year}-{month_map[end_month]}-28"

        metrics = calculate_portfolio_metrics(
            tickers, 
            allocations, 
            start_date, 
            end_date,
            benchmark_ticker
        )
        return jsonify(metrics)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True)