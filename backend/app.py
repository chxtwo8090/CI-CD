# backend/app.py

from flask import Flask, request, jsonify, g
import boto3
import uuid
import datetime
import os
import jwt
from werkzeug.security import generate_password_hash, check_password_hash

# ----------------------------------------------------
# 1. 초기 설정 및 AWS 클라이언트 설정
# ----------------------------------------------------
app = Flask(__name__)
# 로컬 개발 환경에서는 'dummy-secret-key'로 작동하며,
# JWT 토큰 생성 및 검증에 사용됩니다. 운영에서는 반드시 환경 변수로 설정해야 합니다.
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'your-very-secret-key-for-jwt') 

# DynamoDB 테이블 이름 (Terraform에서 정의된 이름)
TABLE_USERS = 'CommunityUsers'
TABLE_POSTS = 'DiscussionPosts'
# TABLE_DATA = 'NaverStockData' # 현재 사용하지 않음

# AWS SDK 클라이언트 설정
try:
    dynamodb = boto3.resource('dynamodb', region_name='ap-northeast-2')
    users_table = dynamodb.Table(TABLE_USERS)
    posts_table = dynamodb.Table(TABLE_POSTS)
except Exception as e:
    print(f"DynamoDB initialization failed: {e}")
    # EKS 환경에서는 IAM Role을 사용하므로, 키 없이 초기화됩니다.

# ----------------------------------------------------
# 2. 유틸리티 함수
# ----------------------------------------------------

# JWT 토큰 검증 데코레이터
def token_required(f):
    def wrapper(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token or not token.startswith('Bearer '):
            return jsonify({'message': 'Token is missing or invalid!'}), 401
        
        token = token.split(' ')[1]
        
        try:
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=["HS256"])
            # 토큰에서 사용자 ID를 추출하여 요청 컨텍스트(g)에 저장
            g.user_id = data['user_id']
        except jwt.ExpiredSignatureError:
            return jsonify({'message': 'Token has expired!'}), 401
        except jwt.InvalidTokenError:
            return jsonify({'message': 'Token is invalid!'}), 401
        
        return f(*args, **kwargs)
    wrapper.__name__ = f.__name__
    return wrapper

# ----------------------------------------------------
# 3. 인증 및 사용자 관리 엔드포인트
# ----------------------------------------------------

@app.route('/register', methods=['POST'])
def register_user():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')
    nickname = data.get('nickname')

    if not all([username, password, nickname]):
        return jsonify({'message': '아이디, 닉네임, 비밀번호를 모두 입력해야 합니다.'}), 400

    # 1. Username 중복 확인 (GSI 사용)
    response = users_table.query(
        IndexName='UsernameIndex',
        KeyConditionExpression='Username = :val',
        ExpressionAttributeValues={':val': username}
    )
    if response['Items']:
        return jsonify({'message': '이미 사용 중인 아이디입니다.'}), 409

    # 2. 새 사용자 생성
    try:
        new_user_id = str(uuid.uuid4()) # 사용자 ID는 UUID로 생성
        hashed_password = generate_password_hash(password)
        
        users_table.put_item(
            Item={
                'UserId': new_user_id,
                'Username': username,
                'Nickname': nickname,
                'PasswordHash': hashed_password,
                'CreatedAt': datetime.datetime.utcnow().isoformat()
            }
        )
        return jsonify({'message': '회원가입 성공'}), 201
    except Exception as e:
        print(f"Registration error: {e}")
        return jsonify({'message': '서버 오류로 회원가입에 실패했습니다.'}), 500


@app.route('/login', methods=['POST'])
def login_user():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    if not all([username, password]):
        return jsonify({'message': '아이디와 비밀번호를 입력해주세요.'}), 400

    # 1. Username으로 사용자 검색 (GSI 사용)
    response = users_table.query(
        IndexName='UsernameIndex',
        KeyConditionExpression='Username = :val',
        ExpressionAttributeValues={':val': username}
    )
    user = response['Items'][0] if response['Items'] else None

    if user and check_password_hash(user['PasswordHash'], password):
        # 2. 로그인 성공: JWT 토큰 생성
        token = jwt.encode({
            'user_id': user['UserId'],
            'username': user['Username'],
            'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=24) # 24시간 유효
        }, app.config['SECRET_KEY'], algorithm="HS256")
        
        # 3. 프론트엔드에 필요한 데이터 전송 (login.html 참조)
        return jsonify({
            'message': '로그인 성공',
            'token': token,
            'user_id': user['UserId'],  
            'nickname': user['Nickname']
        })
    else:
        return jsonify({'message': '아이디 또는 비밀번호가 올바르지 않습니다.'}), 401

# ----------------------------------------------------
# 4. 커뮤니티 게시글 엔드포인트
# ----------------------------------------------------

# [CORS 문제 해결] 모든 응답에 CORS 헤더를 추가합니다.
@app.after_request
def add_cors_headers(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response

# 게시글 생성 (CREATE)
@app.route('/posts', methods=['POST'])
# @token_required # 🛠️ 게시글 작성을 위해 JWT 검증을 활성화해야 함
def create_post():
    data = request.get_json()
    title = data.get('title')
    content = data.get('content')
    author_id = data.get('authorId') # 임시로 authorId를 받음

    if not all([title, content, author_id]):
        return jsonify({'error': '제목, 내용, 작성자 정보가 필요합니다.'}), 400

    try:
        # 1. User 정보 가져오기 (Nickname을 게시글에 저장하기 위함)
        user_response = users_table.get_item(Key={'UserId': author_id})
        user = user_response.get('Item')
        if not user:
             return jsonify({'error': '유효하지 않은 사용자 ID입니다.'}), 400

        # 2. 게시글 저장
        post_id = str(uuid.uuid4())
        stock_code = data.get('stockCode', 'ALL') # 종목 토론방 구분을 위해 기본값 'ALL'
        
        posts_table.put_item(
            Item={
                'StockCode': stock_code,
                'PostId': post_id,
                'Title': title,
                'Content': content,
                'UserId': author_id,
                'AuthorName': user['Nickname'],
                'Views': 0,
                'CreatedAt': datetime.datetime.utcnow().isoformat(),
            }
        )
        return jsonify({'message': '게시글 작성 성공', 'postId': post_id}), 201
    except Exception as e:
        print(f"Post creation error: {e}")
        return jsonify({'error': '게시글 작성 중 서버 오류가 발생했습니다.'}), 500


# ----------------------------------------------------
# 5. LLM 챗봇 엔드포인트 (기능 미구현, 배포 검증용)
# ----------------------------------------------------

@app.route('/chatbot/ask', methods=['POST'])
def chatbot_ask():
    # 이 엔드포인트는 EKS의 LLM 챗봇 서비스로 라우팅될 예정입니다.
    data = request.get_json()
    question = data.get('question', '')
    
    if not question:
        return jsonify({'answer': '질문을 입력해주세요.'}), 200

    # 🚨 로컬 LLM 연동 코드는 여기에 추가됩니다.
    # 현재는 더미 응답을 반환합니다.
    llm_response = f"LLM 챗봇 (Local LLM API) : '{question}'에 대한 답변입니다."
    
    return jsonify({'answer': llm_response}), 200

# ----------------------------------------------------
# 6. 애플리케이션 실행
# ----------------------------------------------------
if __name__ == '__main__':
    # 로컬 테스트용
    app.run(host='0.0.0.0', port=8080)