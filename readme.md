![Image](https://github.com/user-attachments/assets/11527bc9-fa8b-4b99-9d46-d64096116dff)

---

# Install SSH pub key

```bash
bash <(curl -sL https://raw.githubusercontent.com/exhertz/utility/main/install_ssh_key.sh) /path/to_public_key.pub
```

<details>
  <summary>full</summary>

```bash
curl -o install_ssh_key.sh https://raw.githubusercontent.com/exhertz/utility/main/install_ssh_key.sh
chmod +x install_ssh_key.sh
./install_ssh_key.sh /path/to/your/public_key.pub
```
</details>

---

# Enable secure SSH params (sshd_config)

```bash
curl -sL https://raw.githubusercontent.com/exhertz/utility/main/secure_sshd_config.sh | bash
```

<details>
  <summary>full</summary>

```bash
curl -o secure_sshd_config.sh https://raw.githubusercontent.com/exhertz/utility/main/secure_sshd_config.sh
chmod +x secure_sshd_config.sh
./secure_sshd_config.sh
```
</details>

---

# Install and setup UFW

```bash
curl -sL https://raw.githubusercontent.com/exhertz/utility/main/init_ufw.sh | bash
```

<details>
  <summary>full</summary>

```bash
curl -o init_ufw.sh https://raw.githubusercontent.com/exhertz/utility/main/init_ufw.sh
chmod +x init_ufw.sh
./init_ufw.sh
```
</details>