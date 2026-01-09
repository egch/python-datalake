from databricks import sql
import os
from dotenv import load_dotenv

load_dotenv()  # loads .env into environment variables

connection = sql.connect(
    server_hostname=os.getenv("DATABRICKS_HOST"),
    http_path=os.getenv("DATABRICKS_HTTP_PATH"),
    access_token=os.getenv("DATABRICKS_TOKEN"),
)

cursor = connection.cursor()

cursor.execute("SELECT * FROM range(10)")
print(cursor.fetchall())

cursor.close()
connection.close()
