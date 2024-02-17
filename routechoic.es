# http to https
server {
    server_name routechoic.es www.routechoic.es;

    listen 80;
    listen [::]:80;

    if ($bad_referer) {
          return 444;
    }

    return 301 https://$host$request_uri;
}

# Actual redirect
server {
    server_name routechoic.es www.routechoic.es;

    listen [::]:443 ssl;
    listen 443 ssl;

    http2 on;

    listen [::]:443 quic;
    listen 443 quic;

    http3 on;

    quic_gso on;
    quic_retry on;

    add_header alt-svc 'h3=":443"; ma=86400';
    ssl_early_data on;

    ssl_certificate         /etc/letsencrypt/live/routechoic.es/fullchain.pem;
    ssl_certificate_key     /etc/letsencrypt/live/routechoic.es/privkey.pem;

    if ($bad_referer) {
          return 444;
    }

    location / {
      return	301 https://www.routechoices.com$request_uri;
    }
}

# Static file server
# http to https
server {
    server_name cdn.routechoic.es;

    listen 80;
    listen [::]:80;

    if ($bad_referer) {
          return 444;
    }

    return 301 https://$host$request_uri;
}

server {
    server_name cdn.routechoic.es;

    listen [::]:443 ssl;
    listen 443 ssl;
    
    http2 on;

    listen [::]:443 quic;
    listen 443 quic;

    http3 on;

    quic_gso on;
    quic_retry on;

    add_header alt-svc 'h3=":443"; ma=86400';
    ssl_early_data on;

    ssl_certificate         /etc/letsencrypt/live/routechoic.es/fullchain.pem;
    ssl_certificate_key     /etc/letsencrypt/live/routechoic.es/privkey.pem;

    add_header              Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    gzip on;
    gzip_vary on;
    gzip_types application/atom+xml application/javascript application/json application/rss+xml
        application/vnd.ms-fontobject application/x-font-opentype application/x-font-truetype
        application/x-font-ttf application/x-javascript application/xhtml+xml application/xml
        font/eot font/opentype font/otf font/truetype image/svg+xml image/vnd.microsoft.icon
        image/x-icon image/x-win-bitmap text/css text/javascript text/plain text/xml
    gzip_proxied no-cache no-store private expired auth;
    gzip_min_length 1000;
    gzip_comp_level 9;

    brotli on;
    brotli_comp_level 6;
    brotli_types text/plain application/atom+xml application/javascript application/json application/rss+xml
        application/vnd.ms-fontobject application/x-font-opentype application/x-font-truetype
        application/x-font-ttf application/x-javascript application/xhtml+xml application/xml
        font/eot font/opentype font/otf font/truetype image/svg+xml image/vnd.microsoft.icon
        image/x-icon image/x-win-bitmap text/css text/javascript text/xml;
    brotli_static on;

    if ($bad_referer) {
          return 444;
    }

    location /  {
        access_log  off;
        alias       /apps/routechoices-server/static/;
        expires     365d;
        add_header  Cache-Control "public, no-transform";
        add_header  'Access-Control-Allow-Origin' *;
        add_header  'Access-Control-Allow-Methods' 'GET';
        add_header  'Access-Control-Allow-Headers' 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type';
    }
}
