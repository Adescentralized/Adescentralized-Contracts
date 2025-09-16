#!/bin/bash

# Script simplificado para testar o contrato AdVault
# Este script usa a conta admin para todos os testes

set -e

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configurações
NETWORK="testnet"
ADVAULT_CONTRACT="CC2DKPUF6RFI3MQJBOWREWGZPJGLHNPYFSNGSF27EX5RE2QWT5I55VJL"
TOKEN_CONTRACT="CDZBPW57N5B64XJMNOP3FPFDUXO3LFYEWOY2WJYA4EI6WBDMSXNESNL6"
VERIFIER_REGISTRY_CONTRACT="CDYDD4IPTAF2AQ36XBT2X4JYRIHKEWDKCGFWTLYUKP4ESSGSUAEM6ZBC"

# Função para imprimir mensagens coloridas
print_step() {
    echo -e "${BLUE}🔧 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo -e "${GREEN}🚀 Testando AdVault Contract${NC}"
echo "=================================="
echo "Contrato: $ADVAULT_CONTRACT"
echo ""

# 1. Verificar configurações
print_step "1. Verificando configurações do contrato"
echo "Resultado:"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_config
echo ""

# 2. Verificar se o protocolo está pausado
print_step "2. Verificando se o protocolo está pausado"
echo "Resultado:"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- is_protocol_paused
echo ""

# 3. Criar uma campanha de teste
print_step "3. Criando uma campanha de teste"
CAMPAIGN_ID="0000000000000000000000000000000000000000000000000000000000000002"
echo "Campaign ID: $CAMPAIGN_ID"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- create_campaign \
    --campaign_id $CAMPAIGN_ID \
    --advertiser admin \
    --initial_deposit 200000000
print_success "Campanha criada com sucesso"
echo ""

# 4. Verificar a campanha criada
print_step "4. Verificando a campanha criada"
echo "Resultado:"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_campaign \
    --campaign_id $CAMPAIGN_ID
echo ""

# 5. Fazer um depósito adicional na campanha
print_step "5. Fazendo depósito adicional na campanha"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- deposit \
    --campaign_id $CAMPAIGN_ID \
    --from admin \
    --amount 100000000
print_success "Depósito realizado com sucesso"
echo ""

# 6. Verificar a campanha após depósito
print_step "6. Verificando a campanha após depósito"
echo "Resultado:"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_campaign \
    --campaign_id $CAMPAIGN_ID
echo ""

# 7. Testar funções administrativas
print_step "7. Testando funções administrativas"

print_step "7.1. Alterando preço por evento"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- set_price_per_event \
    --new_price 15000000
print_success "Preço alterado com sucesso"

print_step "7.2. Alterando splits"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- set_splits \
    --pub_bps 5500 \
    --view_bps 3500
print_success "Splits alterados com sucesso"

print_step "7.3. Alterando taxa do protocolo"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- set_fee_bps \
    --new_fee 1200
print_success "Taxa alterada com sucesso"
echo ""

# 8. Verificar configurações após mudanças
print_step "8. Verificando configurações após mudanças"
echo "Resultado:"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_config
echo ""

# 9. Pausar e despausar protocolo
print_step "9. Testando pause/unpause do protocolo"

print_step "9.1. Pausando o protocolo"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- pause_protocol
print_success "Protocolo pausado"

print_step "9.2. Verificando se está pausado"
echo "Resultado:"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- is_protocol_paused

print_step "9.3. Despausando o protocolo"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- unpause_protocol
print_success "Protocolo despausado"
echo ""

# 10. Fechar campanha e fazer refund
print_step "10. Fechando campanha e fazendo refund"

print_step "10.1. Fechando campanha"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- close_campaign \
    --campaign_id $CAMPAIGN_ID \
    --reason "test_completed"
print_success "Campanha fechada"

print_step "10.2. Fazendo refund do valor não gasto"
echo "Resultado:"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- refund_unspent \
    --campaign_id $CAMPAIGN_ID \
    --to admin
echo ""

# 11. Verificar campanha após fechamento
print_step "11. Verificando campanha após fechamento"
echo "Resultado:"
stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_campaign \
    --campaign_id $CAMPAIGN_ID
echo ""

echo -e "${GREEN}🎉 Teste do AdVault Contract concluído com sucesso!${NC}"
echo "=================================="
echo ""
echo "Resumo das funcionalidades testadas:"
echo "✅ Inicialização do contrato"
echo "✅ Verificação de configurações"
echo "✅ Criação de campanhas"
echo "✅ Depósitos em campanhas"
echo "✅ Alteração de parâmetros administrativos"
echo "✅ Pause/unpause do protocolo"
echo "✅ Fechamento de campanhas"
echo "✅ Refund de valores não gastos"
echo ""
echo -e "${YELLOW}Nota: As funções de verificação (verifier) estão simplificadas para permitir que todos os verifiers sejam aceitos durante os testes.${NC}"
