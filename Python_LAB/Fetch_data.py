import yfinance as yf
import pandas as pd
import os

# สร้างโฟลเดอร์หลักสำหรับเก็บข้อมูลหุ้น
main_folder = "stock_data"
if not os.path.exists(main_folder):
    os.makedirs(main_folder)

# หุ้นที่ต้องการดึงข้อมูล
symbols = ["ABBV", "SCHD", "ARCC", "MAIN", "LLY", "ABR", "AAAU", "GPIX", "JEPQ", "KR", "QQQI", "O", "ROL", "VICI", "SGOV", "DGRO"]

# ช่วงเวลาที่ต้องการ
period = "max"

# สร้างโฟลเดอร์ย่อยสำหรับประเภทข้อมูลต่างๆ
data_types = ["historical", "info", "financials", "balance_sheet", "cash_flow"]
for data_type in data_types:
    folder_path = os.path.join(main_folder, data_type)
    if not os.path.exists(folder_path):
        os.makedirs(folder_path)

for symbol in symbols:
    try:
        # ดึงข้อมูลหุ้น
        ticker = yf.Ticker(symbol)
        
        # ข้อมูลราคาย้อนหลัง
        historical_data = ticker.history(period=period)
        historical_data.to_csv(f"{main_folder}/historical/{symbol}_historical.csv")
        
        # ข้อมูลพื้นฐาน
        info = ticker.info
        pd.DataFrame(list(info.items()), columns=['Attribute', 'Value']).to_csv(f"{main_folder}/info/{symbol}_info.csv", index=False)
        
        # ข้อมูลงบการเงิน
        financials = ticker.financials
        financials.to_csv(f"{main_folder}/financials/{symbol}_financials.csv")
        
        # งบดุล
        balance_sheet = ticker.balance_sheet
        balance_sheet.to_csv(f"{main_folder}/balance_sheet/{symbol}_balance_sheet.csv")
        
        # งบกระแสเงินสด
        cash_flow = ticker.cashflow
        cash_flow.to_csv(f"{main_folder}/cash_flow/{symbol}_cash_flow.csv")
        
        print(f"บันทึกข้อมูลของ {symbol} เรียบร้อยแล้ว")
    except Exception as e:
        print(f"เกิดข้อผิดพลาดในการดึงข้อมูล {symbol}: {e}")

print(f"เสร็จสิ้น! ไฟล์ CSV ถูกบันทึกในโฟลเดอร์ {main_folder}")