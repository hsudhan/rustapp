. "$HOME/.cargo/env"  
export APP__DATABASE__URL="postgresql://harir@localhost:5432/bankdb"
nohup cargo  run -p party-service & 2>>/dev/null
nohup cargo  run -p corporate-profile-service & 2>>/dev/null
nohup cargo  run -p customer-address-service & 2>>/dev/null
nohup cargo  run -p customer-contact-service & 2>>/dev/null
nohup cargo  run -p customer-employment-service & 2>>/dev/null
nohup cargo  run -p customer-identification-service & 2>>/dev/null
nohup cargo  run -p customer-kyc-service & 2>>/dev/null
nohup cargo  run -p individual-profile-service & 2>>/dev/null