# python-databricks
Access to Databricks via python 

## Setup
Create the env
```shell
python3 -m venv .venv
```

Activate the env
```shell
.venv\Scripts\Activate.ps1
```

Install the libraries
```shell
pip install databricks-sql-connector
pip install databricks-connect
pip install pyodbc
pip install fastapi uvicorn
pip install python-dotenv
```

Freeze the requirements
```shell
 pip freeze > requirements.txt
```

### Check
```shell
 uvicorn main:app --reload 
```
### URL
[health](http://127.0.0.1:8000/health)

[docs](http://127.0.0.1:8000/docs)