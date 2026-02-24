from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import joblib
import pandas as pd
import os

# 1. FastAPIのインスタンス化（1回だけに絞る）
app = FastAPI()

# 2. CORS設定（順序も重要：インスタンス化の直後に行う）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_origin_regex=".*",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 3. モデルの読み込み（パスが正しいことを前提）
# ファイルが存在しない場合に備え、デバッグしやすくしています
try:
    model = joblib.load('penguin_model.joblib')
    model_columns = joblib.load('model_columns.joblib')
except Exception as e:
    print(f"ERROR: Model files not found or failed to load: {e}")

class PenguinData(BaseModel):
    species: str
    island: str
    bill_length_mm: float
    bill_depth_mm: float
    flipper_length_mm: float
    sex: str

@app.get("/")
def read_root():
    return {"status": "Penguin Prediction API is running"}

@app.post("/predict")
def predict(data: PenguinData):
    input_df = pd.DataFrame([data.dict()])
    input_df = pd.get_dummies(input_df)
    
    # 学習時のカラム構成と一致させる
    final_df = pd.DataFrame(columns=model_columns)
    final_df = pd.concat([final_df, input_df]).fillna(0)
    final_df = final_df[model_columns]
    
    prediction = model.predict(final_df)[0]
    return {"predicted_body_mass_g": float(prediction)}

# Cloud Runのエントリポイント
if __name__ == "__main__":
    import uvicorn
    # 環境変数PORTはCloud Run側で自動設定されます
    port = int(os.environ.get("PORT", 8080))
    # host="0.0.0.0" は必須です
    uvicorn.run(app, host="0.0.0.0", port=port)