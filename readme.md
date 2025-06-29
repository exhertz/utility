![Image](https://github.com/user-attachments/assets/11527bc9-fa8b-4b99-9d46-d64096116dff)

---

# Create sudo user

```bash
bash <(curl -sL https://exhertz.github.io/utility/create_sudo_user.sh)
```

---

# Install SSH pub key

```bash
bash <(curl -sL https://exhertz.github.io/utility/install_ssh_key.sh) /path/to_public_key.pub
```

---

# Enable secure SSH params (sshd_config)

```bash
bash <(curl -sL https://exhertz.github.io/utility/secure_sshd_config.sh)
```

---

# Install and setup UFW

```bash
bash <(curl -sL https://exhertz.github.io/utility/init_ufw.sh)
```

---

# Install fail2ban

```bash
bash <(curl -sL https://exhertz.github.io/utility/install_fail2ban.sh)
```

---

# Wireguard

## Server setup

```bash
bash <(curl -sL https://exhertz.github.io/utility/wg/wg-server-setup.sh)
```

## Client setup

```bash
bash <(curl -sL https://exhertz.github.io/utility/wg/wg-client-setup.sh)
```