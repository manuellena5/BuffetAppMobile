from db_utils import get_connection
conn = get_connection()
cursor = conn.cursor()

# Ver nombres de tablas
cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
print(cursor.fetchall())

# Consultar registros de una tabla
cursor.execute("""
                SELECT 'Código', codigo_caja UNION ALL
                SELECT 'Fecha', fecha 
                
                  FROM caja_diaria WHERE id=?
            """, (1,))
for row in cursor.fetchall():
    print(row)

conn.close()