#!/bin/bash

# Script para testar a distribuição de pagamentos do AdVault
# Demonstra como o dinheiro é distribuído para publisher, viewer e protocolo

set -e

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configurações
NETWORK="testnet"
ADVAULT_CONTRACT="CC2DKPUF6RFI3MQJBOWREWGZPJGLHNPYFSNGSF27EX5RE2QWT5I55VJL"
TOKEN_CONTRACT="CDZBPW57N5B64XJMNOP3FPFDUXO3LFYEWOY2WJYA4EI6WBDMSXNESNL6"

print_step() {
    echo -e "${BLUE}🔧 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo -e "${GREEN}💰 Testando Distribuição de Pagamentos AdVault${NC}"
echo "================================================"
echo ""

# 1. Verificar configuração atual de splits
print_step "1. Verificando configuração atual de splits"
CONFIG=$(stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_config 2>/dev/null || echo "")

if [[ $CONFIG =~ \[.*\"([^\"]*)\",\"([^\"]*)\",\"([^\"]*)\",([0-9]+),([0-9]+),([0-9]+),(.*)\] ]]; then
    ADMIN_ADDR="${BASH_REMATCH[1]}"
    TOKEN_ADDR="${BASH_REMATCH[2]}"
    PRICE="${BASH_REMATCH[3]}"
    PUB_BPS="${BASH_REMATCH[4]}"
    VIEW_BPS="${BASH_REMATCH[5]}"
    FEE_BPS="${BASH_REMATCH[6]}"
    PAUSED="${BASH_REMATCH[7]}"
    
    echo "📊 Configuração atual:"
    echo "   Preço por evento: $PRICE stroops"
    echo "   Publisher recebe: $PUB_BPS BPS ($(($PUB_BPS/100)).$(($PUB_BPS%100))%)"
    echo "   Viewer recebe: $VIEW_BPS BPS ($(($VIEW_BPS/100)).$(($VIEW_BPS%100))%)"
    echo "   Taxa protocolo: $FEE_BPS BPS ($(($FEE_BPS/100)).$(($FEE_BPS%100))%)"
else
    print_error "Não foi possível obter configuração do contrato"
    exit 1
fi
echo ""

# 2. Calcular valores de exemplo
print_step "2. Calculando distribuição para um evento"
TOTAL=$PRICE
PUB_AMOUNT=$(($TOTAL * $PUB_BPS / 10000))
VIEW_AMOUNT=$(($TOTAL * $VIEW_BPS / 10000))
FEE_AMOUNT=$(($TOTAL * $FEE_BPS / 10000))

echo "💰 Para um evento de $TOTAL stroops:"
echo "   🏢 Publisher receberia: $PUB_AMOUNT stroops"
echo "   👁️  Viewer receberia: $VIEW_AMOUNT stroops"
echo "   🏛️  Protocolo receberia: $FEE_AMOUNT stroops"
echo "   ✅ Total: $(($PUB_AMOUNT + $VIEW_AMOUNT + $FEE_AMOUNT)) stroops"
echo ""

# 3. Criar uma nova campanha para teste (ou usar existente)
print_step "3. Verificando/Criando campanha para teste de pagamentos"
CAMPAIGN_ID="0000000000000000000000000000000000000000000000000000000000000003"
print_info "Campaign ID: $CAMPAIGN_ID (usando campanha existente)"

# Verificar se a campanha já existe
EXISTING_CAMPAIGN=$(stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_campaign \
    --campaign_id $CAMPAIGN_ID 2>/dev/null || echo "null")

if [ "$EXISTING_CAMPAIGN" = "null" ]; then
    print_error "Campanha não existe. Por favor, execute primeiro o test_advault_simple.sh"
    exit 1
else
    print_success "Usando campanha existente"
    echo "Status: $EXISTING_CAMPAIGN"
fi
echo ""

# 4. Verificar balances antes (simulação)
print_step "4. Preparando para simular um evento de pagamento"
print_info "Em um cenário real, esta função seria chamada por um verifier autorizado"
print_info "quando um usuário clica ou visualiza um anúncio."
echo ""

# 5. Criar estrutura de Attestation para submit_event
print_step "5. Criando estrutura de evento (Attestation)"

# Gerar IDs únicos baseados no timestamp atual
TIMESTAMP=$(date +%s)
EVENT_ID=$(printf "%064d" $TIMESTAMP)
NONCE_ID=$(printf "%064d" $(($TIMESTAMP + 1)))

echo "📋 Dados do evento:"
echo "   Event ID: $EVENT_ID"
echo "   Campaign ID: $CAMPAIGN_ID"
echo "   Publisher: admin (quem hospeda)"
echo "   Viewer: admin (quem vê o anúncio)"
echo "   Tipo: click"
echo "   Timestamp: $TIMESTAMP"
echo "   Nonce: $NONCE_ID"
echo ""

# 6. Tentar submeter o evento (vai funcionar porque simplificamos a verificação)
print_step "6. Submetendo evento para processamento de pagamento"
print_info "Nota: Como simplificamos a verificação no contrato, qualquer verifier é aceito"

print_info "Executando submit_event..."
RESULT=$(stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- submit_event \
    --att "{\"campaign_id\":\"$CAMPAIGN_ID\",\"event_id\":\"$EVENT_ID\",\"event_kind\":\"click\",\"nonce\":\"$NONCE_ID\",\"publisher\":\"GBJTQSNVXNGBXGWZLGBT7YGGU6JGSNN276E6EEP3M54DUVAFY2SBWFWU\",\"timestamp\":$TIMESTAMP,\"viewer\":\"GBJTQSNVXNGBXGWZLGBT7YGGU6JGSNN276E6EEP3M54DUVAFY2SBWFWU\"}" \
    --verifier GBJTQSNVXNGBXGWZLGBT7YGGU6JGSNN276E6EEP3M54DUVAFY2SBWFWU 2>&1)

if [[ $? -eq 0 ]]; then
    print_success "Evento processado com sucesso!"
    echo "$RESULT"
    
    # Extrair valores retornados se possível
    if [[ $RESULT =~ \[\"([0-9]+)\",\"([0-9]+)\",\"([0-9]+)\"\] ]]; then
        ACTUAL_PUB="${BASH_REMATCH[1]}"
        ACTUAL_VIEW="${BASH_REMATCH[2]}"
        ACTUAL_FEE="${BASH_REMATCH[3]}"
        
        echo ""
        print_success "💰 Distribuição realizada:"
        echo "   🏢 Publisher recebeu: $ACTUAL_PUB stroops"
        echo "   👁️  Viewer recebeu: $ACTUAL_VIEW stroops"
        echo "   🏛️  Protocolo recebeu: $ACTUAL_FEE stroops"
        echo "   📊 Total distribuído: $(($ACTUAL_PUB + $ACTUAL_VIEW + $ACTUAL_FEE)) stroops"
    fi
else
    print_error "Erro ao processar evento:"
    echo "$RESULT"
fi
echo ""

# 7. Verificar campanha após pagamento
print_step "7. Verificando campanha após pagamento"
CAMPAIGN_AFTER=$(stellar contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_campaign \
    --campaign_id $CAMPAIGN_ID 2>/dev/null)

echo "📊 Status da campanha:"
echo "$CAMPAIGN_AFTER"
echo ""

# 8. Explicar como funciona na prática
print_step "8. Como funciona na prática"
cat << EOF
🎯 Fluxo de Pagamento Descentralizado:

1️⃣ ADVERTISER cria campanha e deposita tokens
2️⃣ PUBLISHER exibe anúncio em seu site
3️⃣ VIEWER interage com o anúncio (clique/visualização)
4️⃣ VERIFIER (oráculo) valida a interação e chama submit_event
5️⃣ CONTRATO distribui automaticamente:
   • Publisher recebe pela hospedagem
   • Viewer recebe por interagir
   • Protocolo recebe taxa de serviço

✨ Tudo acontece de forma automática e transparente na blockchain!
EOF
echo ""

echo -e "${GREEN}🎉 Demonstração de distribuição de pagamentos concluída!${NC}"
echo "================================================"
