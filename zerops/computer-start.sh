zerops:
  # ---------- API + browser worker, autoscaling ----------
  - setup: app
    build:
      base: nodejs@24
      os: ubuntu
      buildCommands:
        - npx -y pnpm@11.19.0 install --frozen-lockfile --config.node-linker=hoisted
        - npx -y pnpm@11.19.0 build:server
        - cd apps/worker && npm ci --omit=dev --ignore-scripts
        - mkdir -p bin && curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-27.5.1.tgz | tar -xz -C bin --strip-components=1 docker/docker
      deployFiles:
        - ./dist
        - ./node_modules
        - ./package.json
        - ./apps/worker
        - ./bin
    run:
      base: nodejs@24
      os: ubuntu
      prepareCommands:
        - sudo apt-get update
        - sudo apt-get install -y rclone
        - sudo mkdir -p /opt/ms-playwright
        - sudo chmod 777 /opt/ms-playwright
        - sudo env "PATH=$PATH" npx -y playwright@1.62.1 install-deps chromium
        - PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright npx -y playwright@1.62.1 install chromium
      volume:
        hostname: vol
        mountPath: /mnt/vol
      envVariables:
        NODE_ENV: production
        PATH: /var/www/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        # API
        HOST: 0.0.0.0
        PORT: "8787"
        WORKSPACE_MODE: live
        AGENT_BACKEND: model
        # Model: OPENAI_BASE_URL + OPENAI_API_KEY are secrets on the service
        MODEL: openai/REPLACE_MODEL_ID          # keep the openai/ prefix, e.g. openai/vendor/model-name
        DATA_DIR: /mnt/vol/openmuse
        TASK_WORKER_ENABLED: "true"
        BROWSER_WORKER_URL: http://127.0.0.1:8790
        COMPUTER_ENABLED: "true"
        COMPUTER_IMAGE: openmuse-computer:local
        COMPUTER_DEPLOYMENT_ID: openmuse
        DOCKER_HOST: tcp://computer:2376
        DOCKER_TLS_VERIFY: "1"
        DOCKER_CERT_PATH: /mnt/vol/certs
        # Uncomment after the first deploy with your real URL:
        # PUBLIC_API_URL: https://APP_URL_FROM_ZEROPS
        # Browser worker (same container, loopback only)
        WORKER_HOST: 127.0.0.1
        WORKER_DATA_DIR: /mnt/vol/browser
        PLAYWRIGHT_BROWSERS_PATH: /opt/ms-playwright
        # Backups
        RCLONE_CONFIG_R2_TYPE: s3
        RCLONE_CONFIG_R2_PROVIDER: Cloudflare
        RCLONE_CONFIG_R2_REGION: auto
        RCLONE_CONFIG_R2_ACL: private
        R2_BUCKET: openmuse-backup
      startCommands:
        - name: browser
          command: node --experimental-strip-types apps/worker/src/index.ts
          initCommands:
            - mkdir -p /mnt/vol/browser
        - name: api
          command: node dist/apps/server/src/index.js
          initCommands:
            - mkdir -p /mnt/vol/openmuse /mnt/vol/backup /mnt/vol/certs
            - printf '%s' "$DOCKER_CA_B64" | base64 -d > /mnt/vol/certs/ca.pem
            - printf '%s' "$DOCKER_CLIENT_CERT_B64" | base64 -d > /mnt/vol/certs/cert.pem
            - printf '%s' "$DOCKER_CLIENT_KEY_B64" | base64 -d > /mnt/vol/certs/key.pem
            - chmod 600 /mnt/vol/certs/*.pem
      ports:
        - port: 8787
          httpSupport: true
      crontab:
        - command: >
            set -e;
            STAMP=$(date -u -I);
            tar -czf /mnt/vol/backup/openmuse-$STAMP.tar.gz -C /mnt/vol openmuse browser;
            rclone copyto /mnt/vol/backup/openmuse-$STAMP.tar.gz r2:$R2_BUCKET/openmuse/openmuse-$STAMP.tar.gz;
            rclone copyto /mnt/vol/backup/openmuse-$STAMP.tar.gz r2:$R2_BUCKET/openmuse/latest.tar.gz;
            find /mnt/vol/backup -name 'openmuse-*.tar.gz' -mtime +3 -delete;
            rclone delete r2:$R2_BUCKET/openmuse/ --min-age 30d --include 'openmuse-*.tar.gz'
          timing: "45 3 * * *"
          allContainers: false

  # ---------- Linux computer, fixed tiny Docker VM ----------
  - setup: computer
    build:
      base: ubuntu@22.04
      buildCommands:
        - echo "nothing to build"
      deployFiles:
        - ./apps/computer
        - ./zerops/computer-start.sh
    run:
      base: docker@26.1
      prepareCommands:
        - docker image pull docker:27.5.1-dind
        - docker image pull node:22.22.0-bookworm-slim
      start: sh zerops/computer-start.sh
      ports:
        - port: 2376
          protocol: tcp
