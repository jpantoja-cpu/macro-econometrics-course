"""Base de datos de Bolivia para el TVAR de El Niño (rama bolivia-nino).

    import sys; sys.path.append("..")
    import datos_bolivia as db
    ipc = db.load()                 # copia congelada, trimestral
    ipc = db.load(refresh=True)     # descarga de nuevo desde el INE

Sigue la lógica de ``course_data.py``: una copia congelada en
``bolivia/datos_bolivia.csv`` para reproducir resultados, y una descarga
opcional. Trimestres completos, promedio de los meses, fechados el primer día
del último mes del trimestre (marzo, junio, setiembre, diciembre).
"""
from __future__ import annotations

import sys
import urllib.request
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
sys.path.append(str(HERE.parent))
import course_data as cd  # noqa: E402  (para reutilizar _quarterly)

DATA = HERE / "datos_bolivia.csv"
RAW_IPC = HERE / "ipc_ine_raw.xlsx"            # base 2016 = 100, desde enero de 2018
RAW_IPC_HIST = HERE / "ipc_ine_hist_raw.xlsx"  # base 2007 = 100, marzo 2008 a diciembre 2017
RAW_IPC_1991 = HERE / "ipc_ine_1991_raw.xls"   # base 1991 = 100, marzo 1992 a marzo 2008 (Excel antiguo: requiere xlrd)

# INE, enlaces públicos de nube.ine.gob.bo
URL_IPC = "https://nube.ine.gob.bo/index.php/s/auAr2RoVf2ya2Eu/download"
URL_IPC_HIST = "https://nube.ine.gob.bo/index.php/s/kVGgyqtobYRsZwv/download"
URL_IPC_1991 = "https://nube.ine.gob.bo/index.php/s/LzucAyViXN7ikbL/download"
HOJA_IPC = "CUADRO Nº 1.1 ÍNDICE MENSUAL"
HOJA_IPC_VAR = "CUADRO Nº 1.2 VAR MENSUAL"
HOJA_IPC_HIST = "indgeneral"
HOJA_IPC_1991 = "INDGRAL"

MESES = {"enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6,
         "julio": 7, "agosto": 8, "septiembre": 9, "setiembre": 9, "octubre": 10,
         "noviembre": 11, "diciembre": 12}


def _download(url: str, path: Path) -> Path:
    """Descarga un Excel del INE (requiere internet en tu máquina)."""
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    path.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    return path


def download_ipc() -> None:
    _download(URL_IPC, RAW_IPC)
    _download(URL_IPC_HIST, RAW_IPC_HIST)
    _download(URL_IPC_1991, RAW_IPC_1991)


def read_table(path: Path, sheet: str, name: str = "ipc") -> pd.Series:
    """Cuadro del INE con meses en filas y años en columnas, a serie mensual."""
    raw = pd.read_excel(path, sheet_name=sheet, header=None)
    fila = raw.index[raw.iloc[:, 0].astype(str).str.strip().str.upper() == "MES"][0]
    años = raw.iloc[fila, 1:]
    values = {}
    for _, row in raw.iloc[fila + 1:].iterrows():
        mes = MESES.get(str(row.iloc[0]).strip().lower())
        if mes is None:                       # salta filas vacías, promedio anual y fuente
            continue
        for año, v in zip(años, row.iloc[1:]):
            v = pd.to_numeric(v, errors="coerce")
            if pd.notna(año) and pd.notna(v):
                values[pd.Timestamp(int(año), mes, 1)] = float(v)
    return pd.Series(values, name=name).sort_index()


def read_ipc() -> pd.Series:
    """IPC mensual empalmado, base 2016 = 100, desde marzo de 1992.

    Tres bases del INE encadenadas hacia atrás, sin tocar ninguna variación
    mensual publicada:
      * 2007 -> 2016: no se solapan (dic-2017 / ene-2018). Se usa la variación
        oficial de ene-2018 en base 2016 (cuadro 1.2):
        dic-2017 x (1 + var. ene-2018) = ene-2018.
      * 1991 -> 2007: se solapan en un solo mes, mar-2008, que es el enlace.
    """
    nueva = read_table(RAW_IPC, HOJA_IPC)
    b07 = read_table(RAW_IPC_HIST, HOJA_IPC_HIST)
    b91 = read_table(RAW_IPC_1991, HOJA_IPC_1991)
    var = read_table(RAW_IPC, HOJA_IPC_VAR, "var")

    enlace = nueva.index[0]                                  # 2018-01
    dic17 = enlace - pd.DateOffset(months=1)                 # 2017-12
    b07 = b07 * (nueva[enlace] / (1 + var[enlace] / 100) / b07[dic17])
    b07 = b07.loc[:dic17]

    mar08 = b07.index[0]                                     # 2008-03, único mes común
    b91 = (b91 * (b07[mar08] / b91[mar08])).loc[:mar08 - pd.DateOffset(months=1)]
    return pd.concat([b91, b07, nueva]).rename("ipc")


def build(refresh: bool = False) -> pd.DataFrame:
    """Arma la base trimestral desde el Excel (descargándolo si refresh=True)."""
    if refresh or not all(p.exists() for p in (RAW_IPC, RAW_IPC_HIST, RAW_IPC_1991)):
        download_ipc()
    ipc = cd._quarterly(read_ipc(), "M")       # solo trimestres completos
    return ipc.to_frame("ipc")


def load(refresh: bool = False) -> pd.DataFrame:
    """Base trimestral de Bolivia. Por defecto la copia congelada."""
    if refresh or not DATA.exists():
        df = build(refresh=refresh)
        if not DATA.exists():
            df.to_csv(DATA)                    # primera vez: crea la copia congelada
        return df
    return pd.read_csv(DATA, index_col="date", parse_dates=True)


def freeze() -> None:
    """Reemplaza la copia congelada con lo que hay en el Excel descargado."""
    build(refresh=False).to_csv(DATA)


if __name__ == "__main__":
    freeze()
    print(load().tail())
