#!/bin/bash
# Lab 17 — Data Pipeline Engineering (Track 2) — Bash wrapper for Git Bash / WSL
# Usage: make <target> [options]
# Example: make run
#          make day DAY=2026-08-14
#          make help

set -e

# Configuration
VENV="${VENV:-.venv}"
PY="${VENV}/bin/python"
DBT="$(cd "${VENV}" 2>/dev/null && pwd)/bin/dbt"
DAY="${DAY:-2026-08-12}"
export DO_NOT_TRACK=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
test_venv_exists() {
    [ -d "$VENV" ]
}

test_dbt_exists() {
    [ -f "$DBT" ]
}

show_help() {
    echo -e "\n${GREEN}Usage:${NC}"
    echo -e "  ${CYAN}make <target>${NC}\n"
    echo -e "${CYAN}Targets:${NC}"
    echo "  help              Show this help"
    echo "  setup             Create .venv + install the lite-path deps"
    echo "  setup-dbt         Add dbt-core + dbt-duckdb to .venv (dbt track)"
    echo "  run               Fresh build: reset Silver/Gold, backfill 08-10..08-16 from Bronze"
    echo "  day               One daily run on the existing warehouse (set DAY=2026-08-14)"
    echo "  lateness          Measure event lateness (P50/P95/P99) from Bronze"
    echo "  rerun3            GRADING TEST: fresh build, re-run 2026-08-12 three times"
    echo "  verify            All pipeline contracts (18 checks)"
    echo "  test              pytest (unit tests + table contracts + extensions)"
    echo "  dbt               dbt track: land Bronze, dbt build"
    echo "  parity            dbt track: same Bronze in -> same checksum out (lite vs dbt)"
    echo "  bonus-llm         Bonus: LLM labelling step with hash cache + validation"
    echo "  flywheel          Extension (ungraded): agent traces -> eval set + DPO pairs"
    echo "  kg                Extension (ungraded): knowledge graph vs vector retrieval"
    echo "  docker-up         Bonus: the same daily run on real Airflow 3"
    echo "  clean             Remove venv and everything the pipeline built"
    echo ""
}

target_setup() {
    if test_venv_exists; then
        echo -e "${YELLOW}Virtual environment already exists at $VENV${NC}"
        return
    fi
    echo -e "${CYAN}Creating virtual environment...${NC}"
    python3 -m venv "$VENV"
    echo -e "${CYAN}Installing dependencies...${NC}"
    "$PY" -m pip -q install -r requirements.txt
    echo -e "${GREEN}Setup complete!${NC}"
}

target_setup_dbt() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Installing dbt dependencies...${NC}"
    "$PY" -m pip -q install -r requirements-dbt.txt
    echo -e "${GREEN}dbt setup complete!${NC}"
}

target_run() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Running pipeline (fresh build)...${NC}"
    "$PY" main.py
}

target_day() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Running daily pipeline for $DAY...${NC}"
    "$PY" main.py --date "$DAY"
}

target_lateness() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Measuring event lateness...${NC}"
    "$PY" main.py --lateness
}

target_rerun3() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Running rerun3 test...${NC}"
    "$PY" -m scripts.rerun_check
}

target_verify() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Verifying pipeline contracts...${NC}"
    "$PY" -m scripts.verify
}

target_test() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Running pytest...${NC}"
    "$PY" -m pytest
}

target_dbt() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    if ! test_dbt_exists; then
        echo -e "${RED}Error: dbt not found. Run 'make setup-dbt' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Landing Bronze and running dbt build...${NC}"
    "$PY" main.py --land-only > /dev/null
    (
        cd dbt_project
        export DBT_PROFILES_DIR="."
        "$DBT" build --event-time-start 2026-08-10 --event-time-end 2026-08-17
    )
}

target_parity() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Checking parity (lite vs dbt)...${NC}"
    "$PY" -m scripts.parity
}

target_bonus_llm() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Running bonus LLM script...${NC}"
    "$PY" -m scripts.bonus_llm
}

target_flywheel() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Running flywheel extension...${NC}"
    "$PY" -m extensions.flywheel
}

target_kg() {
    if ! test_venv_exists; then
        echo -e "${RED}Error: Virtual environment not found. Run 'make setup' first.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Running knowledge graph extension...${NC}"
    "$PY" -m extensions.kg_demo
}

target_docker_up() {
    echo -e "${CYAN}Starting Docker Airflow...${NC}"
    docker compose -f docker/docker-compose.yml up
}

target_clean() {
    echo -e "${YELLOW}Cleaning up venv, lake, warehouse, and cache files...${NC}"
    rm -rf "$VENV" lake warehouse.duckdb warehouse.duckdb.wal datasets .pytest_cache \
           dbt_project/dbt.duckdb dbt_project/target dbt_project/logs
    find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
    echo -e "${GREEN}Clean complete!${NC}"
}

# Main execution
case "${1:-help}" in
    help)           show_help ;;
    setup)          target_setup ;;
    setup-dbt)      target_setup_dbt ;;
    run)            target_run ;;
    day)            target_day ;;
    lateness)       target_lateness ;;
    rerun3)         target_rerun3 ;;
    verify)         target_verify ;;
    test)           target_test ;;
    dbt)            target_dbt ;;
    parity)         target_parity ;;
    bonus-llm)      target_bonus_llm ;;
    flywheel)       target_flywheel ;;
    kg)             target_kg ;;
    docker-up)      target_docker_up ;;
    clean)          target_clean ;;
    *)
        echo -e "${RED}Unknown target: $1${NC}"
        show_help
        exit 1
        ;;
esac
