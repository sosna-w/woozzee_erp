whoami
cd ~
pwd
mkdir -p app
cd app
mkdir logs
mkdir backups
pwd
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
python app.py
python -c "
from app import app
from database import init_db
with app.app_context():
    init_db()
    print('Database tables created successfully')
"
deactivate
exit
cd /home/flaskapp/app
source venv/bin/activate
pip install gunicorn
gunicorn --workers 1 --bind 127.0.0.1:5000 app:app
exit
cd /home/flaskapp/app
rm -f employees.db
source venv/bin/activate
python -c "
from app import Base, engine
Base.metadata.create_all(bind=engine)
print('Database tables created successfully')
"
exit
cd /home/flaskapp/app
source venv/bin/activate
pip install requests
pip install urllib3
exit
