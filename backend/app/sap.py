"""Integração com o SAP.

Todo acesso ao SAP passa por este módulo, para que o resto da API não saiba
de onde os dados vêm. A origem é escolhida pela variável SAP_PROVIDER:

- "catalog" (padrão): tabela sap_catalog, preenchida importando um arquivo
  CSV/Excel exportado do SAP. Funciona hoje, sem acesso à rede da empresa.
- "odata": consulta direta ao SAP (S/4HANA OData ou BTP). Ainda não
  implementado: depende do TI definir versão, serviço e acesso.

A exportação de horas fica em export_entries_csv, num layout próximo ao do
apontamento de horas do SAP (CATS).
"""

import csv
import datetime as dt
import io
import os

# Colunas aceitas no arquivo do catálogo (cabeçalho, sem diferenciar maiúsculas).
CATALOG_COLUMNS = {
    "projeto": "code",
    "cliente": "client",
    "pep": "sap_wbs",
    "ordem_venda": "sap_sales_order",
    "horas_previstas": "budget_hours",
    "data_entrega": "due_date",
}
CATALOG_TEMPLATE = "projeto;cliente;pep;ordem_venda;horas_previstas;data_entrega\n"


class SapNotConfigured(Exception):
    """A origem escolhida em SAP_PROVIDER ainda não está disponível."""


def provider() -> str:
    return os.environ.get("SAP_PROVIDER", "catalog").strip().lower()


def lookup_project(conn, code: str) -> dict | None:
    """Dados do projeto no SAP pelo número, ou None se não existir."""
    code = code.strip().upper()
    if provider() == "catalog":
        row = conn.execute(
            """SELECT code, client, sap_wbs, sap_sales_order, budget_hours, due_date
               FROM sap_catalog WHERE code = ?""",
            (code,),
        ).fetchone()
        return dict(row) if row else None
    raise SapNotConfigured(
        f"SAP_PROVIDER={provider()!r} ainda não implementado. Use 'catalog' até o TI liberar o acesso ao SAP."
    )


def _parse_hours(text: str) -> float | None:
    text = text.strip().replace(".", "").replace(",", ".") if "," in text else text.strip()
    if not text:
        return None
    value = float(text)
    if value <= 0:
        raise ValueError("horas previstas precisam ser maiores que zero")
    return value


def _parse_date(text: str) -> str | None:
    text = text.strip()
    if not text:
        return None
    for fmt in ("%d/%m/%Y", "%Y-%m-%d", "%d.%m.%Y"):  # dd.mm.aaaa é o formato padrão do SAP
        try:
            return dt.datetime.strptime(text, fmt).date().isoformat()
        except ValueError:
            pass
    raise ValueError(f"data inválida {text!r} (use dd/mm/aaaa)")


def parse_catalog(text: str) -> tuple[list[dict], list[str]]:
    """Lê o CSV (separado por ; , ou tab, como sai do Excel) e devolve (linhas válidas, erros)."""
    text = text.lstrip("﻿").strip()
    if not text:
        return [], ["Arquivo vazio."]
    first = text.splitlines()[0]
    delimiter = max(";,\t", key=first.count)
    reader = csv.DictReader(io.StringIO(text), delimiter=delimiter)
    headers = {h.strip().lower(): h for h in reader.fieldnames or []}
    missing = [c for c in ("projeto", "cliente") if c not in headers]
    if missing:
        return [], [f"Faltam as colunas: {', '.join(missing)}. Modelo: {CATALOG_TEMPLATE.strip()}"]

    rows, errors = [], []
    for line, raw in enumerate(reader, start=2):
        values = {CATALOG_COLUMNS[k]: (raw.get(h) or "").strip() for k, h in headers.items() if k in CATALOG_COLUMNS}
        if not values.get("code"):
            if any(values.values()):
                errors.append(f"Linha {line}: sem número do projeto.")
            continue
        try:
            values["code"] = values["code"].upper()
            values["budget_hours"] = _parse_hours(values.get("budget_hours", ""))
            values["due_date"] = _parse_date(values.get("due_date", ""))
        except ValueError as e:
            errors.append(f"Linha {line}: {e}.")
            continue
        rows.append(values)
    return rows, errors


def import_catalog(conn, rows: list[dict]) -> int:
    """Insere ou atualiza os projetos do catálogo (o número do projeto é a chave)."""
    for r in rows:
        conn.execute(
            """INSERT INTO sap_catalog (code, client, sap_wbs, sap_sales_order, budget_hours, due_date)
               VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT (code) DO UPDATE SET
                   client = excluded.client, sap_wbs = excluded.sap_wbs,
                   sap_sales_order = excluded.sap_sales_order, budget_hours = excluded.budget_hours,
                   due_date = excluded.due_date""",
            (
                r["code"],
                r.get("client", ""),
                r.get("sap_wbs", ""),
                r.get("sap_sales_order", ""),
                r.get("budget_hours"),
                r.get("due_date"),
            ),
        )
    return len(rows)


EXPORT_COLUMNS = [
    "data", "projeto", "pep", "ordem_venda", "cliente", "funcionario", "email", "atividade",
    "inicio", "fim", "intervalo_min", "horas", "status", "descricao",
]


def export_entries_csv(rows: list[dict]) -> str:
    """CSV para Excel em português: separador ;, vírgula decimal, data dd.mm.aaaa (como no SAP).

    O SAP identifica o funcionário pelo nº pessoal; por enquanto vai o e-mail,
    até o TI definir esse mapeamento.
    """
    out = io.StringIO()
    out.write("﻿")  # BOM: o Excel reconhece os acentos
    writer = csv.writer(out, delimiter=";", lineterminator="\r\n")
    writer.writerow(EXPORT_COLUMNS)
    for r in rows:
        writer.writerow([
            dt.date.fromisoformat(r["work_date"]).strftime("%d.%m.%Y"),
            r["project_code"],
            r["sap_wbs"],
            r["sap_sales_order"],
            r["client"],
            r["user_name"],
            r["user_email"],
            r["activity_name"] or "",
            r["start_time"] or "",
            r["end_time"] or "",
            r["break_minutes"] if r["start_time"] else "",
            f"{r['hours']:.2f}".replace(".", ","),
            r["status"],
            r["description"],
        ])
    return out.getvalue()
