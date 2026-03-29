# 🛡️ AEGIS

### Serverless Mesh Communication for Sovereign Connectivity

<p align="center">
  <b>Private. Decentralized. Unstoppable.</b><br>
  <i>When the towers fall, the mesh lives.</i>
</p>

---

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android-blue?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Flutter-Frontend-02569B?style=for-the-badge&logo=flutter"/>
  <img src="https://img.shields.io/badge/Kotlin-Native-orange?style=for-the-badge&logo=kotlin"/>
  <img src="https://img.shields.io/badge/Encryption-Libsodium-green?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Architecture-P2P-red?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge"/>
</p>

---

## 🚀 Overview

**AEGIS** is a next-generation **secure peer-to-peer communication system** that eliminates centralized servers. It enables **fully private, encrypted messaging** that works even without internet infrastructure.

Unlike traditional apps, AEGIS is built on a **zero-trust architecture** — no servers, no metadata, no surveillance.

---

## ✨ Key Highlights

* 🔐 **End-to-End Encryption** (Libsodium)
* 🧩 **Fully Serverless Architecture**
* 🕵️ **Zero Metadata Tracking**
* 💀 **Ephemeral Messaging (Auto-Destruct)**
* 🧠 **GhostID (Anonymous Identity)**
* 📡 **Mesh Networking (WiFi Direct + BLE)**
* 🔁 **Forward Secrecy (Double Ratchet)**
* 🌐 **Works Without Internet**

---

## 🧠 Architecture

```text
Flutter UI
   ↓
Kotlin Native Layer (WiFi Direct / BLE)
   ↓
P2P Communication (Mesh Network)
   ↓
Libsodium Encryption
   ↓
Peer Device
```

---

## 🔄 How It Works

```text
1. Generate cryptographic identity (public/private key)
2. Discover nearby peers (WiFi Direct / BLE)
3. Perform secure handshake (X3DH)
4. Establish P2P connection
5. Encrypt & send message
6. Decrypt on receiver side
7. Auto-delete via TTL (Reaper)
```

---

## 📸 Screenshots

> Add your app screenshots here

```md
![Home](assets/screens/home.png)
![Chat](assets/screens/chat.png)
![Radar](assets/screens/radar.png)
```

---

## 🔐 Security Model

* Zero-trust communication
* End-to-end encryption
* Forward secrecy
* No central server
* No metadata storage

---

## 🎯 Use Cases

* 🚨 Disaster communication (no infrastructure)
* 🕵️ Privacy-first messaging
* 📰 Secure journalism
* 🏢 Enterprise secure communication

---

## ⚠️ Limitations

* Limited range (current version)
* No multi-hop routing (planned)
* Device compatibility constraints

---

## 🛠️ Tech Stack

| Layer      | Technology                |
| ---------- | ------------------------- |
| Frontend   | Flutter                   |
| Transport  | Kotlin (WiFi Direct, BLE) |
| Encryption | Libsodium                 |
| Storage    | SQLCipher                 |
| Protocols  | X3DH, Double Ratchet      |

---

## 🚀 Getting Started

### Prerequisites

* Flutter SDK
* Android Studio
* Kotlin setup

### Run the App

```bash
git clone https://github.com/your-username/aegis.git
cd aegis
flutter pub get
flutter run
```

---

## 📦 Project Structure

```text
/lib        → Flutter UI  
/android    → Kotlin native layer  
/crypto     → Encryption modules  
/assets     → Images & UI resources  
```

---

## 🤝 Contributing

We welcome contributions!

```bash
# Fork the repo
# Create your feature branch
git checkout -b feature/awesome-feature

# Commit changes
git commit -m "Add awesome feature"

# Push
git push origin feature/awesome-feature
```

---

## 📜 License

MIT License © 2025

---

## 👥 Team

**Code Predators**

* Vishwas Dubey
* Kundan Kumar
* Dheeraj Kumar
* Amritanshu Kumar

---

## 🌟 Support

If you like this project:
⭐ Star this repo
🍴 Fork it
📢 Share it

---

## 💡 Final Thought

> AEGIS is not just a messaging app —
> it is a step toward **sovereign, censorship-resistant communication**.
