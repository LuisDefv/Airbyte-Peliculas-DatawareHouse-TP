# Airbyte · Películas · Data Warehouse (TP)

Data Warehouse que **integra dos fuentes**: el catálogo de Netflix (8.807 títulos) y el de Amazon Prime Video (9.668 títulos), siguiendo la arquitectura de Inmon (*Corporate Information Factory*).

```
netflix_titles.csv ──┐                    ┌─ raw  (staging, lo escribe Airbyte; volátil)
                     ├─Airbyte─▶ Postgres ┼─ dwh  (EDW integrado, no volátil)  ◀── CALL dwh.sp_cargar_dwh()
amazon_prime_titles ─┘                    └─ mart (estrella, vistas) ──▶ Power BI
```

## 1. Data warehouse (PostgreSQL en Docker)

```bash
docker run -d --name netflix-dw -e POSTGRES_USER=netflix -e POSTGRES_PASSWORD=<tu_password> \
  -e POSTGRES_DB=netflix_dw -p 5434:5432 --restart unless-stopped postgres:16
docker exec -it netflix-dw psql -U netflix -d netflix_dw -c "CREATE SCHEMA IF NOT EXISTS raw;"
```

## 2. Airbyte (`abctl local install`, UI en http://localhost:8000)

| Pieza | Configuración |
|---|---|
| **Source 1** `File` | `Netflix CSV (GitHub)`: URL `https://raw.githubusercontent.com/LuisDefv/Airbyte-Peliculas-DatawareHouse-TP/main/netflix_titles.csv`, CSV, HTTPS, dataset `netflix_titles` |
| **Source 2** `File` | `Amazon Prime CSV (GitHub)`: URL `.../main/amazon_prime_titles.csv`, CSV, HTTPS, dataset `amazon_prime_titles` |
| **Destination** `Postgres` | host `host.docker.internal`, puerto `5434`, DB `netflix_dw`, schema `raw`, user `netflix`, SSL disabled |
| **Connections** | una por fuente, *Full refresh – Overwrite*, schedule manual |

> **Importante:** no crear vistas sobre las tablas de `raw`. Con *Overwrite* Airbyte borra y recrea esas tablas en cada sync y PostgreSQL no lo permite si hay vistas que dependen de ellas (el sync falla con `cannot drop table ... because other objects depend on it`).

## 3. EDW integrado y data mart

```bash
docker exec -i netflix-dw psql -U netflix -d netflix_dw < sql/02_edw_integrado.sql
docker exec -i netflix-dw psql -U netflix -d netflix_dw < sql/03_data_mart.sql
# después de cada sync de Airbyte:
docker exec netflix-dw psql -U netflix -d netflix_dw -c "CALL dwh.sp_cargar_dwh();"
```

| Esquema | Contenido |
|---|---|
| `raw` | `netflix_titles`, `amazon_prime_titles` (Airbyte) |
| `dwh` | `titulo`, `titulo_genero`, `titulo_pais`, `plataforma`, `map_clasificacion`, `map_genero`, `control_carga` + `sp_cargar_dwh()` |
| `mart` | `fact_titulo`, `dim_plataforma`, `dim_clasificacion`, `dim_anio`, `dim_genero` + `bridge_titulo_genero`, `dim_pais` + `bridge_titulo_pais`, `calidad_fuente` |

Integración aplicada: clave `(plataforma, show_id)`, 26 códigos de clasificación por edad homologados en 5 grupos, 70 géneros unificados en 24, duración separada en minutos/temporadas, fechas de texto a `date`, corrección de 3 filas con la duración en `rating`. La carga es un upsert: nunca borra (no volatilidad) y registra cada ejecución en `dwh.control_carga` (variación en el tiempo).

`sql/01_modelo_dw.sql` es el modelo de la primera entrega (solo Netflix, vistas sobre `raw`); se reemplazó por el de arriba. Sus definiciones quedaron respaldadas en `sql/backup_vistas_dw_legacy.sql`.

## 4. Power BI

`powerbi/StreamingDashboard.pbip` (proyecto de texto: modelo en TMDL y reporte en PBIR). Abrirlo con Power BI Desktop → **Inicio → Actualizar → Esquema y datos**. Credenciales de **Base de datos**: usuario `netflix`. Tiene tres páginas: *Comparativa de plataformas*, *Contenido y calidad de datos* y *Solo series*.

`powerbi/NetflixDashboard.pbip` es el tablero de la primera entrega (apunta a las vistas `dw` que ya no existen).

## Cómo levantar todo de nuevo

1. Ejecutar `..\Prender Airbyte.bat` como administrador (prende Docker, libera puertos de WinNAT y levanta Airbyte).
2. `docker start netflix-dw` si el Postgres no arrancó solo.
3. Sincronizar las dos conexiones en Airbyte y correr `CALL dwh.sp_cargar_dwh();`.
4. Abrir `powerbi\StreamingDashboard.pbip` y **Actualizar**.

### Nota sobre el puerto de Kubernetes de Airbyte

El 29/10/2026 Windows bloqueó el rango de puertos 62187–64162 (no lo liberaba ni reiniciando WinNAT) y el nodo `airbyte-abctl-control-plane` no podía publicar su API en el 62814. Se recreó el contenedor del nodo publicando la API en **127.0.0.1:61814**, reutilizando su volumen y la carpeta `~/.airbyte/abctl/data`, y se actualizó `~/.airbyte/abctl/abctl.kubeconfig`. El contenedor viejo quedó como `airbyte-abctl-control-plane-backup` (detenido).
