"""Base de datos de Bolivia para el TVAR de El Niño (rama bolivia-nino).

    import sys; sys.path.append("..")
    import datos_bolivia as db
    df = db.load()                  # copia congelada, trimestral: pib, pib_agro, ipc
    df = db.load(refresh=True)      # descarga de nuevo desde el INE

Sigue la lógica de ``course_data.py``: una copia congelada en
``bolivia/datos_bolivia.csv`` para reproducir resultados, y una descarga
opcional. Trimestres completos, promedio de los meses, fechados el primer día
del último mes del trimestre (marzo, junio, setiembre, diciembre).
"""
from __future__ import annotations

import re
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

# INE, PIB trimestral real
RAW_PIB = HERE / "pib_ine_2017_raw.xlsx"        # volumen encadenado (ref. 2017), 2017T1 en adelante
RAW_PIB_1990 = HERE / "pib_ine_1990_raw.xlsx"   # Bs de 1990, 1990T1 a 2024T4
URL_PIB = "https://nube.ine.gob.bo/index.php/s/1RFsK6XS7ZuMXaH/download"
URL_PIB_1990 = "https://nimbus.ine.gob.bo/index.php/s/LgCGFBWiz2QccwP/download"
TRIM = {"I": 1, "II": 2, "III": 3, "IV": 4}

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


def download_pib() -> None:
    _download(URL_PIB, RAW_PIB)
    _download(URL_PIB_1990, RAW_PIB_1990)


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


def _fecha(year: int, q: int) -> pd.Timestamp:
    return pd.Timestamp(year, 3 * q, 1)        # trimestre fechado en su último mes


def read_pib_1990(path: Path = RAW_PIB_1990) -> pd.DataFrame:
    """Cuadro 1.01.01: años y trimestres en filas, actividades en columnas."""
    d = pd.read_excel(path, header=None)
    hdr = d.index[d.apply(lambda r: r.astype(str).str.strip().eq("PERIODO").any(), axis=1)][0]
    cols = d.iloc[hdr].astype(str).str.strip()
    c_per = cols[cols == "PERIODO"].index[0]
    c_agro = cols[cols.str.startswith("AGRICULTURA")].index[0]
    c_pib = cols[cols.str.startswith("PIB A PRECIOS DE MERCADO")].index[0]
    out, year = {}, None
    for _, r in d.iloc[hdr + 1:].iterrows():
        lab = str(r[c_per]).strip()
        m = re.match(r"^(\d{4})", lab)
        if m:                                   # fila del año (total anual): marca el año
            year = int(m.group(1))
            continue
        q = TRIM.get(lab.split()[0]) if lab.split() else None
        if q and year and pd.notna(r[c_pib]):
            out[_fecha(year, q)] = {"pib": float(r[c_pib]), "pib_agro": float(r[c_agro])}
    return pd.DataFrame(out).T.sort_index()


def read_pib_2017(path: Path = RAW_PIB) -> pd.DataFrame:
    """Cuadro 02.01: actividades en filas, años y trimestres en columnas."""
    d = pd.read_excel(path, header=None)
    lab = d.iloc[:, 1].astype(str).str.strip()
    hdr = lab[lab.str.startswith("ACTIVIDAD")].index[0]
    years, qs = d.iloc[hdr].ffill(), d.iloc[hdr + 1]
    r_pib = lab[lab.str.startswith("PRODUCTO INTERNO BRUTO")].index[0]
    r_agro = lab[lab.str.startswith("AGRICULTURA")].index[0]
    out = {}
    for c in range(2, d.shape[1]):
        y, q = re.match(r"(\d{4})", str(years[c])), TRIM.get(str(qs[c]).strip())
        if y and q and pd.notna(d.iloc[r_pib, c]):
            out[_fecha(int(y.group(1)), q)] = {"pib": float(d.iloc[r_pib, c]),
                                               "pib_agro": float(d.iloc[r_agro, c])}
    return pd.DataFrame(out).T.sort_index()


def read_pib() -> pd.DataFrame:
    """PIB total y agropecuario, en millones de Bs encadenados (ref. 2017), desde 1990T1.

    Retropolación: desde 2017 manda la serie nueva; antes, la de base 1990
    reescalada trimestre por trimestre con el cociente nuevo/viejo de cada
    trimestre de 2017. Con un factor por trimestre, las tasas interanuales
    hasta 2017 son exactamente las de base 1990 y desde 2018 las de la serie
    nueva. Las dos bases difieren bastante en 2018-2024 (la nueva es una
    revisión metodológica), así que el tramo reciente usa la oficial vigente."""
    nueva, vieja = read_pib_2017(), read_pib_1990()
    enlace = nueva.loc["2017"]
    factor = (enlace / vieja.loc[enlace.index]).groupby(enlace.index.quarter).first()
    q = vieja.index.quarter
    vieja = vieja.mul(factor.loc[q].to_numpy()).loc[:enlace.index[0] - pd.DateOffset(months=3)]
    return pd.concat([vieja, nueva])



# ------------------------------------------------ PIB departamental (anual)
DIR_DEP = HERE / "pib_dep"                      # un Excel por departamento, Bs de 1990, 1988-2024
URL_DEP = {
    "chuquisaca": "hHU8psn75hWR8fV", "la_paz": "JGySvLfLxfxhIzb", "cochabamba": "TPp9wVaoTi9eRxp",
    "oruro": "PycgCZK6K6siAJc", "potosi": "NkBlw9xk2zTIcFO", "tarija": "vILrN7dlWg53tMl",
    "santa_cruz": "WFE06wQEezoctP5", "beni": "f5jJXWvS5DT3joh", "pando": "K9n4oiVsQoPyBsu",
}
REGIONES = {
    "altiplano": ["la_paz", "oruro", "potosi"],
    "valles": ["cochabamba", "chuquisaca", "tarija"],
    "llanos": ["santa_cruz", "beni", "pando"],
}
# filas del cuadro x.01.01 que se leen (prefijo del texto, sin espacios iniciales)
FILAS_DEP = {
    "pib": "PRODUCTO INTERNO BRUTO (a precios de mercado)",
    "agro": "1. Agricultura",
    "agro_no_ind": "- Productos Agrícolas no Industriales",
    "agro_ind": "- Productos Agrícolas Industriales",
    "coca": "- Coca",
    "pecuario": "- Productos Pecuarios",
}
DATA_REG = HERE / "pib_regiones.csv"


def download_dep() -> None:
    DIR_DEP.mkdir(exist_ok=True)
    for dep, code in URL_DEP.items():
        _download(f"https://nube.ine.gob.bo/index.php/s/{code}/download", DIR_DEP / f"pib_{dep}.xlsx")


def read_dep(dep: str) -> pd.DataFrame:
    """Un departamento: años en filas, rubros de FILAS_DEP en columnas (miles de Bs de 1990)."""
    d = pd.read_excel(DIR_DEP / f"pib_{dep}.xlsx", header=None)
    lab = d.iloc[:, 1].astype(str).str.strip() if d.shape[1] > 1 else None
    col_lab = next(c for c in range(d.shape[1])
                   if d.iloc[:, c].astype(str).str.contains("ACTIVIDAD").any())
    lab = d.iloc[:, col_lab].astype(str).str.strip()
    hdr = lab[lab.str.startswith("ACTIVIDAD")].index[0]
    años = {c: int(re.match(r"(\d{4})", str(v)).group(1)) for c, v in d.iloc[hdr].items()
            if c != col_lab and re.match(r"(\d{4})", str(v))}
    out = {}
    for name, pref in FILAS_DEP.items():
        r = lab[lab.str.startswith(pref)].index[0]
        out[name] = pd.Series({a: float(d.iloc[r, c]) for c, a in años.items()})
    return pd.DataFrame(out)


def pib_regiones(refresh: bool = False) -> pd.DataFrame:
    """PIB anual por región (suma de departamentos, miles de Bs de 1990).
    Columnas multinivel: (región, rubro). Incluye 'bolivia' como suma de las tres."""
    if refresh or not all((DIR_DEP / f"pib_{d}.xlsx").exists() for d in URL_DEP):
        download_dep()
    deps = {d: read_dep(d) for d in URL_DEP}
    reg = {r: sum(deps[d] for d in ds) for r, ds in REGIONES.items()}
    reg["bolivia"] = sum(reg.values())
    df = pd.concat(reg, axis=1)
    df.index.name = "año"
    df.to_csv(DATA_REG)
    return df

def build(refresh: bool = False) -> pd.DataFrame:
    """Arma la base trimestral desde el Excel (descargándolo si refresh=True)."""
    if refresh or not all(p.exists() for p in (RAW_IPC, RAW_IPC_HIST, RAW_IPC_1991)):
        download_ipc()
    if refresh or not all(p.exists() for p in (RAW_PIB, RAW_PIB_1990)):
        download_pib()
    ipc = cd._quarterly(read_ipc(), "M").rename("ipc")   # solo trimestres completos
    df = read_pib().join(ipc, how="outer")
    df.index.name = "date"
    return df[["pib", "pib_agro", "ipc"]]


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
