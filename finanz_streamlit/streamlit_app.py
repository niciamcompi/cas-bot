import pandas as pd
import streamlit as st

BASE_URL = "https://raw.githubusercontent.com/datasets"
SP500_URL = f"{BASE_URL}/s-and-p-500/main/data/data.csv"
FINANCIALS_URL = (
    f"{BASE_URL}/s-and-p-500-companies-financials/main/data/constituents-financials.csv"
)
GICS_URL = f"{BASE_URL}/s-and-p-500-companies/main/data/constituents.csv"
BLUE = "#0068C9"
RED = "#FF2B2B"


@st.cache_data(ttl=3600)
def load_data() -> tuple[pd.DataFrame, pd.DataFrame]:
    sp500 = (
        pd.read_csv(SP500_URL, parse_dates=["Date"])
        .rename(
            columns={
                "Date": "Datum",
                "SP500": "Index",
                "Long Interest Rate": "Zins 10J",
                "PE10": "Shiller KGV",
            }
        )
        .loc[:, ["Datum", "Index", "Zins 10J", "Shiller KGV"]]
        .replace({"Zins 10J": {0: pd.NA}, "Shiller KGV": {0: pd.NA}})
        .astype({"Zins 10J": "Float64", "Shiller KGV": "Float64"})
        .query("Datum >= '1950-01-01'")
        .assign(Jahr=lambda d: d["Datum"].dt.year)
    )
    gics = pd.read_csv(GICS_URL).loc[:, ["Symbol", "GICS Sector"]]
    companies = (
        pd.read_csv(FINANCIALS_URL)
        .merge(gics, on="Symbol", how="left")
        .rename(
            columns={
                "Sector": "Branche",
                "GICS Sector": "Sektor",
                "Price": "Kurs",
                "Price/Earnings": "KGV",
                "Dividend Yield": "Dividendenrendite",
                "Market Cap": "Marktkapitalisierung",
            }
        )
        .assign(
            Sektor=lambda d: d["Sektor"].fillna("Unbekannt"),
            Marktkap_mrd=lambda d: d["Marktkapitalisierung"] / 1e9,
        )
    )
    return sp500, companies


st.set_page_config(page_title="Finanz-Dashboard", page_icon="📈", layout="wide")
sp500, companies = load_data()

tab_markt, tab_firmen = st.tabs(["📈 S&P 500 Markt", "🏢 Unternehmen"])

with tab_markt:
    st.title("S&P 500 – Markt seit 1950")
    latest = sp500.iloc[-1]
    year_ago = sp500.loc[sp500["Datum"] == latest["Datum"] - pd.DateOffset(years=1)]
    return_12m = latest["Index"] / year_ago["Index"].iloc[0] - 1
    col_1, col_2, col_3, col_4 = st.columns(4)
    col_1.metric("Aktueller Indexstand", f"{latest['Index']:,.0f}", border=True)
    col_2.metric(
        "Rendite 12 Monate",
        f"{return_12m:.1%}",
        delta=f"{return_12m:.1%}",
        border=True,
    )
    col_3.metric(
        "Shiller-KGV (CAPE)",
        f"{sp500['Shiller KGV'].dropna().iloc[-1]:.1f}",
        border=True,
    )
    col_4.metric("Ø Zins 10J (%)", f"{sp500['Zins 10J'].mean():.2f}", border=True)

    col_left, col_right = st.columns([2, 1])
    with col_left, st.container(border=True):
        st.subheader("Indexverlauf")
        st.area_chart(sp500, x="Datum", y="Index", color=BLUE)
    with col_right, st.container(border=True):
        st.subheader("Zinsen vs. Bewertung")
        st.line_chart(sp500, x="Datum", y=["Zins 10J", "Shiller KGV"])

    annual_returns = (
        sp500.groupby("Jahr", as_index=False)["Index"]
        .last()
        .assign(
            Jahresrendite=lambda d: d["Index"].pct_change() * 100,
            Farbe=lambda d: d["Jahresrendite"].ge(0).map({True: BLUE, False: RED}),
        )
        .dropna(subset=["Jahresrendite"])
    )
    with st.container(border=True):
        st.subheader("Jahresrendite (%)")
        st.bar_chart(annual_returns, x="Jahr", y="Jahresrendite", color="Farbe")

with tab_firmen:
    st.title("S&P 500 – Unternehmen nach Sektor")
    sectors = ["Alle", *sorted(companies["Sektor"].unique())]
    sector = st.selectbox("Sektor", sectors)
    selection = companies if sector == "Alle" else companies.query("Sektor == @sector")

    col_1, col_2, col_3 = st.columns(3)
    col_1.metric("Anzahl Unternehmen", f"{len(selection):,}", border=True)
    col_2.metric(
        "Marktkapitalisierung",
        f"{selection['Marktkap_mrd'].sum():,.0f} Mrd. USD",
        border=True,
    )
    col_3.metric(
        "Ø Dividendenrendite",
        f"{selection['Dividendenrendite'].mean():.2%}",
        border=True,
    )

    by_sector = (
        selection.groupby("Sektor", as_index=False)
        .agg(
            Marktkap_mrd=("Marktkap_mrd", "sum"),
            Median_KGV=("KGV", "median"),
        )
        .sort_values("Marktkap_mrd", ascending=False)
    )
    col_left, col_right = st.columns(2)
    with col_left, st.container(border=True):
        st.subheader("Marktkapitalisierung nach Sektor (Mrd. USD)")
        st.bar_chart(
            by_sector,
            x="Sektor",
            y="Marktkap_mrd",
            horizontal=True,
            x_label="Mrd. USD",
            y_label="",
            sort="-Marktkap_mrd",
            color=BLUE,
        )
    with col_right, st.container(border=True):
        st.subheader("Median-KGV nach Sektor")
        st.bar_chart(
            by_sector,
            x="Sektor",
            y="Median_KGV",
            sort="-Median_KGV",
            color=BLUE,
            x_label="",
            y_label="Median-KGV",
        )

    with st.container(border=True):
        st.subheader("Grösste Unternehmen")
        st.dataframe(
            selection.sort_values("Marktkap_mrd", ascending=False).loc[
                :,
                [
                    "Symbol",
                    "Name",
                    "Sektor",
                    "Branche",
                    "Kurs",
                    "KGV",
                    "Dividendenrendite",
                    "Marktkap_mrd",
                ],
            ],
            hide_index=True,
            width="stretch",
            column_config={
                "Kurs": st.column_config.NumberColumn(format="%.2f"),
                "KGV": st.column_config.NumberColumn(format="%.1f"),
                "Dividendenrendite": st.column_config.NumberColumn(format="percent"),
                "Marktkap_mrd": st.column_config.NumberColumn(
                    "Marktkap. (Mrd. USD)", format="%.1f"
                ),
            },
        )

st.caption(
    "Daten: github.com/datasets (S&P 500, Unternehmenskennzahlen, GICS-Sektoren)"
)
