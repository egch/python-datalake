# python-databricks
Access to Databricks via python 

## Setup
Create the env
```shell
python3 -m venv .venv
```

Activate the env - Windows
```shell
.venv\Scripts\Activate.ps1
```

Activate the env - Mac
```shell
source .venv/bin/activate
```


Install the libraries
```shell

pip install fastapi uvicorn azure-storage-file-datalake pyarrow
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

### .env
Add a `.env` file with the access key of your ADSL
```properties
ADLS_ACCOUNT_KEY=<YOUR_ACCESS_KEY>

```
### URL
[health](http://127.0.0.1:8000/health)

[docs](http://127.0.0.1:8000/docs)