ARG AWS_CLI_IMAGE=amazon/aws-cli:2.40.4
FROM ${AWS_CLI_IMAGE}
COPY sync.sh /usr/local/bin/sync.sh
RUN chmod 0755 /usr/local/bin/sync.sh
ENTRYPOINT ["/usr/local/bin/sync.sh"]
CMD ["run"]
