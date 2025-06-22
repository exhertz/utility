![Image](https://github.com/user-attachments/assets/11527bc9-fa8b-4b99-9d46-d64096116dff)

# Install SSH pub key
one line:
```bash
curl -sL https://raw.githubusercontent.com/exhertz/utility/main/install_ssh_key.sh | bash -s -- /path/to_public_key.pub
```
or:
```bash
curl -o install_ssh_key.sh https://raw.githubusercontent.com/exhertz/utility/main/install_ssh_key.sh
chmod +x install_ssh_key.sh
./install_ssh_key.sh /path/to/your/public_key.pub
```