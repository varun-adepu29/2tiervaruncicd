#!/bin/bash
exec > /var/log/setup.log 2>&1

echo "Starting setup..."

# ---------- Values from Terraform ----------
DB_HOST="${DB_HOST}"
DB_USER="${DB_USER}"
DB_PASSWORD="${DB_PASSWORD}"
DB_NAME="${DB_NAME}"

# ---------- Persist ENV globally ----------
cat <<EOF > /etc/profile.d/app_env.sh
export DB_HOST="${DB_HOST}"
export DB_USER="${DB_USER}"
export DB_PASSWORD="${DB_PASSWORD}"
export DB_NAME="${DB_NAME}"
EOF

chmod +x /etc/profile.d/app_env.sh
source /etc/profile.d/app_env.sh

# Also for non-login services
echo "DB_HOST=${DB_HOST}" >> /etc/environment
echo "DB_USER=${DB_USER}" >> /etc/environment
echo "DB_PASSWORD=${DB_PASSWORD}" >> /etc/environment
echo "DB_NAME=${DB_NAME}" >> /etc/environment

echo "ENV variables configured"

# ---------- System setup ----------
apt update -y && apt upgrade -y
apt install -y python3 python3-pip mysql-client

# ---------- App directory ----------
APP_DIR=/home/azureuser/student-app
mkdir -p ${APP_DIR}
cd ${APP_DIR}

# ---------- Python packages ----------
pip3 install flask flask-sqlalchemy pymysql gunicorn

# ---------- config.py (ENV BASED) ----------
cat <<EOF > config.py
import os

class Config:
    DB_HOST     = os.environ.get("DB_HOST")
    DB_USER     = os.environ.get("DB_USER")
    DB_PASSWORD = os.environ.get("DB_PASSWORD")
    DB_NAME     = os.environ.get("DB_NAME")

    SQLALCHEMY_DATABASE_URI = (
        f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}"
        "?ssl_ca=/etc/ssl/certs/ca-certificates.crt"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
EOF

# ---------- app.py ----------
cat <<'EOF' > app.py
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from config import Config

app = Flask(__name__)
app.config.from_object(Config)
db  = SQLAlchemy(app)

class Student(db.Model):
    __tablename__ = 'students'
    id     = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name   = db.Column(db.String(100), nullable=False)
    email  = db.Column(db.String(120), unique=True, nullable=False)
    course = db.Column(db.String(100), default='General')

    def to_dict(self):
        return {'id':self.id,'name':self.name,'email':self.email,'course':self.course}

@app.route('/')
def home():
    return jsonify({'message': 'Student Registration API is running on Azure!'})

@app.route('/students', methods=['GET'])
def get_all_students():
    return jsonify([s.to_dict() for s in Student.query.all()])

@app.route('/students', methods=['POST'])
def add_student():
    data = request.get_json()
    student = Student(name=data['name'], email=data['email'],
                      course=data.get('course','General'))
    db.session.add(student)
    db.session.commit()
    return jsonify({'message':'Student added!','student':student.to_dict()}), 201

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    app.run(host='0.0.0.0', port=5000)
EOF

# ---------- Wait for DB ----------
sleep 30

# ---------- Create DB ----------
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" --ssl-mode=REQUIRED \
  -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"

# ---------- Test DB ----------
python3 - <<PY
import os, pymysql
conn = pymysql.connect(
  host=os.environ['DB_HOST'],
  user=os.environ['DB_USER'],
  password=os.environ['DB_PASSWORD'],
  database=os.environ['DB_NAME'],
  ssl={'ssl_ca':'/etc/ssl/certs/ca-certificates.crt'}
)
print("DB CONNECT OK")
conn.close()
PY

# ---------- Start app ----------
nohup python3 app.py > app.log 2>&1 &

echo "Setup completed"