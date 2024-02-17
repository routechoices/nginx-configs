server {
    server_name routechoices.com *.routechoices.com;

    listen [::]:443 ssl reuseport;
    listen 443 ssl reuseport;

    http2 on;

    listen [::]:443 quic reuseport;
    listen 443 quic reuseport;
    
    http3 on;
    
    quic_gso on;
    quic_retry on;

    add_header alt-svc 'h3=":443"; ma=86400';
    ssl_early_data on;

    ssl_certificate	/etc/letsencrypt/live/routechoices.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/routechoices.com/privkey.pem;

    add_header		Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    
    if ($host = routechoices.com) {
        return 301 https://www.routechoices.com$request_uri;
    }

    gzip		on;
    gzip_vary		on;
    gzip_types		text/plain text/css text/xml text/javascript application/javascript application/xml application/json image/svg+xml;
    gzip_proxied	no-cache no-store private expired auth;
    gzip_min_length	1000;
    gzip_comp_level	9;

    brotli		on;
    brotli_comp_level	2;
    brotli_types	text/plain text/css text/xml text/javascript application/javascript application/xml application/json image/svg+xml;
    brotli_static	on;

    if ($bad_referer) {
          return 444;
    }

    location /internal/  {
        internal;
        alias /apps/routechoices-server/media/;
    }

    location  ~ ^/s3/(.*) {
        internal;
        chunked_transfer_encoding off;
        proxy_http_version        1.1;
        proxy_set_header          Connection "";
        proxy_set_header          Authorization '';
        proxy_hide_header         x-amz-id-2;
        proxy_hide_header         x-amz-request-id;
        proxy_hide_header         x-amz-meta-server-side-encryption;
        proxy_hide_header         x-amz-server-side-encryption;
        proxy_hide_header         Set-Cookie;
        proxy_ignore_headers      Set-Cookie;
        proxy_pass                http://127.0.0.1:9000/$1;
        proxy_hide_header	  Content-Type;
        proxy_intercept_errors    on;
    }

    location /static/  {
        access_log	off;
        alias		/apps/routechoices-server/static/;
        expires		365d;
	add_header	Cache-Control "public, no-transform";
        add_header	'Access-Control-Allow-Origin' *;
        add_header	'Access-Control-Allow-Methods' 'GET';
        add_header	'Access-Control-Allow-Headers' 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type';
	add_header	X-Cache $upstream_cache_status;
    }

    location / {
        # Setup var defaults
        set $no_cache "";
        # If non GET/HEAD, don't cache & mark user as uncacheable for 1 second via cookie
        if ($request_method !~ ^(GET|HEAD)$) {
            set $no_cache "1";
        }
        if ($uri ~ ^(\/dashboard|\/admin)) {
            set $no_cache "1";
	}
        # Drop no cache cookie if need be
        # (for some reason, add_header fails if included in prior if-block)
        if ($no_cache = "1") {
            add_header Set-Cookie "_mcnc=1; Max-Age=2; Path=/";            
            add_header X-Microcachable "0";
        }
        # Bypass cache if no-cache cookie is set
        if ($http_cookie ~* "_mcnc") {
            set $no_cache "1";
        }
        # Set cache zone
        uwsgi_cache microcache;
        # Set cache key to include identifying components
        uwsgi_cache_key $scheme$host$request_method$request_uri;
        # Only cache valid HTTP 200 responses for 1 second
        uwsgi_cache_valid 200 1s;
        # Serve from cache if currently refreshing
        uwsgi_cache_use_stale updating;
        # Send appropriate headers through
        # Set files larger than 10M to stream rather than cache
        uwsgi_max_temp_file_size 5M;
        # Bypass cache if flag is set
        uwsgi_no_cache $no_cache;
        uwsgi_cache_bypass $no_cache;

        proxy_read_timeout	300;
        proxy_connect_timeout	300;
        proxy_send_timeout	300;

        client_max_body_size    20M;

        proxy_set_header        Host   $host;
        proxy_set_header        X-Real-IP $remote_addr;
        proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto 'https';
        proxy_set_header        X-Forwarded-Host $host;
        uwsgi_pass              unix:///apps/routechoices-server/var/django.sock;
        uwsgi_param             HTTP_HOST $host;
        uwsgi_pass_header       Host;
        uwsgi_pass_header       Authorization;
        uwsgi_hide_header       X-Accel-Redirect;
        uwsgi_hide_header       X-Sendfile;
        uwsgi_intercept_errors  off;
        include                 uwsgi_params;
    }
    
    location = /api/ping {
    	# Plausible docker
        resolver 		1.1.1.1;
        proxy_pass		https://analytics.routechoices.com/api/event;

        proxy_buffering		on;
        proxy_http_version	1.1;

        proxy_set_header	Host analytics.routechoices.com;
        proxy_ssl_name		analytics.routechoices.com;
        proxy_ssl_server_name	on;
        proxy_ssl_session_reuse off;

        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $host;
    }
}

# http to https
server {
    server_name routechoices.com *.routechoices.com;
    
    listen [::]:80;
    listen 80;
    
    if ($bad_referer) {
          return 444;
    }

    return 301 https://$host$request_uri;
}

server {
    server_name analytics.routechoices.com;

    listen 443 ssl;
    listen [::]:443 ssl;

    http2 on;

    listen 443 quic;
    listen [::]:443 quic;

    http3 on;

    quic_gso on;
    quic_retry on;

    add_header alt-svc 'h3=":443"; ma=86400';
    ssl_early_data on;

    ssl_certificate	/etc/letsencrypt/live/routechoices.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/routechoices.com/privkey.pem;
    
    if ($bad_referer) {
          return 444;
    }

    location /images/icon/plausible_logo-973ea42fac38d21a0a8cda9cfb9231c9.png {
       root /apps/plausible/overrules/;
    }

    location / {
    	# plausible analytics docker
        proxy_pass		http://127.0.0.1:8086;
        proxy_redirect		off;
        proxy_set_header Host	$http_host;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $host;
        proxy_connect_timeout	1;
        proxy_send_timeout	120;
        proxy_read_timeout	120;
    }
}

server {
    server_name tile-proxy.routechoices.com;

    listen 443 ssl;
    listen [::]:443 ssl;    

    http2 on;

    listen 443 quic;
    listen [::]:443 quic;

    http3 on;

    quic_gso on;
    quic_retry on;

    add_header alt-svc 'h3=":443"; ma=86400';
    ssl_early_data on;

    ssl_certificate	/etc/letsencrypt/live/routechoices.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/routechoices.com/privkey.pem;

    if ($bad_referer) {
          return 444;
    }

    location /  {
        access_log off;
	# flask app (mapant tile proxy)
        proxy_pass	http://127.0.0.1:19651;
        add_header	Cache-Control "public, no-transform";
        add_header	'Access-Control-Allow-Origin' *;
        add_header	'Access-Control-Allow-Methods' 'GET';
        add_header	'Access-Control-Allow-Headers' 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type';
    }
}

server {
    server_name map-download.routechoices.com;

    listen 443 ssl;
    listen [::]:443 ssl;

    http2 on;

    listen 443 quic;
    listen [::]:443 quic;

    http3 on;

    quic_gso on;
    quic_retry on;

    add_header alt-svc 'h3=":443"; ma=86400';
    ssl_early_data on;

    ssl_certificate	/etc/letsencrypt/live/routechoices.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/routechoices.com/privkey.pem;

    client_max_body_size 20M;

    if ($bad_referer) {
          return 444;
    }

    location /  {
        access_log off;
	# flask app (mapant tile proxy)
        proxy_pass	http://127.0.0.1:3526;
        add_header	Cache-Control "public, no-transform";
        add_header	'Access-Control-Allow-Origin' *;
        add_header	'Access-Control-Allow-Methods' 'GET';
        add_header	'Access-Control-Allow-Headers' 'DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type';
    }
}

server {
    server_name livelox-map.routechoices.com routegadget-map.routechoices.com ocad-map.routechoices.com;

    listen 443 ssl;
    listen [::]:443 ssl;

    http2 on;

    listen 443 quic;
    listen [::]:443 quic;

    http3 on;

    quic_gso on;
    quic_retry on;

    add_header alt-svc 'h3=":443"; ma=86400';
    ssl_early_data on;

    ssl_certificate	/etc/letsencrypt/live/routechoices.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/routechoices.com/privkey.pem;

    if ($bad_referer) {
          return 444;
    }

    if ($host = livelox-map.routechoices.com) {
        return 301 https://map-download.routechoices.com/livelox/;
    }
    if ($host = ocad-map.routechoices.com) {
        return 301 https://map-download.routechoices.com/ocad/;
    }
    if ($host = routegadget-map.routechoices.com) {
        return 301 https://map-download.routechoices.com/routegadget/;
    }
}
