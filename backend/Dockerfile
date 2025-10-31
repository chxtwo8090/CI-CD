# backend/Dockerfile

FROM python:3.9-slim

# 환경 변수 설정
ENV PYTHONUNBUFFERED 1
ENV FLASK_APP app.py
ENV FLASK_ENV production

WORKDIR /app

# 의존성 복사 및 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 애플리케이션 코드 복사
COPY app.py .
 
# 8080 포트를 노출합니다 (Service.targetPort와 일치)
EXPOSE 8080 

# Gunicorn을 사용하여 Flask 앱 실행 (운영 환경 권장 방식)
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8080", "app:app"]