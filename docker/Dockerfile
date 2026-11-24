FROM nginx:1.27-alpine

RUN apk add --no-cache aws-cli bash python3

COPY nginx.conf /etc/nginx/nginx.conf
COPY scripts/sync.py /usr/local/bin/sync.py
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Run as the built-in unprivileged nginx user; it must own the web root and work dir.
RUN chmod +x /usr/local/bin/sync.py /usr/local/bin/entrypoint.sh \
 && mkdir -p /tmp/s3-sync \
 && echo '{"result":"pending"}' > /usr/share/nginx/html/status.json \
 && chown -R nginx:nginx /usr/share/nginx/html /tmp/s3-sync

USER nginx
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
