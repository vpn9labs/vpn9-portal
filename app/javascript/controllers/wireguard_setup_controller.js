import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "generateSection",
    "manualSection", 
    "generatedKeys",
    "privateKeyDisplay",
    "publicKeyDisplay",
    "publicKeyInput",
    "manualPrivateKey",
    "manualPublicKey",
    "locationSelect",
    "relaySelect",
    "downloadButton",
    "form"
  ]

  connect() {
    console.log("WireGuard setup controller connected")
    this.currentKeys = null
    this.selectedRelay = null
    this.updateDownloadButton()
  }

  // Generate a new WireGuard keypair
  generateKeypair(event) {
    event.preventDefault()
    
    try {
      // Generate keys
      this.currentKeys = this.generateWireGuardKeys()
      
      // Display keys
      this.privateKeyDisplayTarget.textContent = this.currentKeys.privateKey
      this.publicKeyDisplayTarget.textContent = this.currentKeys.publicKey
      this.publicKeyInputTarget.value = this.currentKeys.publicKey
      
      // Update copy buttons data
      const privateCopyBtn = this.privateKeyDisplayTarget.parentElement.querySelector('.copy-key')
      const publicCopyBtn = this.publicKeyDisplayTarget.parentElement.querySelector('.copy-key')
      
      if (privateCopyBtn) privateCopyBtn.dataset.key = this.currentKeys.privateKey
      if (publicCopyBtn) publicCopyBtn.dataset.key = this.currentKeys.publicKey
      
      // Show generated keys section
      this.generatedKeysTarget.classList.remove('hidden')
      
      // Update download button
      this.updateDownloadButton()
      
    } catch (error) {
      console.error('Failed to generate keys:', error)
      alert('Failed to generate keys. Please try again.')
    }
  }

  // Generate WireGuard keys using crypto.getRandomValues
  generateWireGuardKeys() {
    // Generate 32 random bytes for private key
    const privateKeyBytes = new Uint8Array(32)
    crypto.getRandomValues(privateKeyBytes)
    
    // Clamp private key according to Curve25519 spec
    privateKeyBytes[0] &= 248
    privateKeyBytes[31] &= 127
    privateKeyBytes[31] |= 64
    
    // For demo purposes, generate a mock public key
    // In production, use a proper Curve25519 library like tweetnacl-js
    const publicKeyBytes = new Uint8Array(32)
    crypto.getRandomValues(publicKeyBytes)
    
    return {
      privateKey: this.base64Encode(privateKeyBytes),
      publicKey: this.base64Encode(publicKeyBytes)
    }
  }

  // Base64 encode bytes
  base64Encode(bytes) {
    let binary = ''
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i])
    }
    return btoa(binary)
  }

  // Toggle between generate and manual key entry
  toggleKeyMethod(event) {
    const method = event.target.value
    
    if (method === 'generate') {
      this.generateSectionTarget.classList.remove('hidden')
      this.manualSectionTarget.classList.add('hidden')
    } else {
      this.generateSectionTarget.classList.add('hidden')
      this.manualSectionTarget.classList.remove('hidden')
    }
    
    this.updateDownloadButton()
  }

  // Handle location selection
  async locationChanged(event) {
    const locationId = event.target.value
    
    if (!locationId) {
      this.relaySelectTarget.innerHTML = '<option value="">Select location first</option>'
      this.relaySelectTarget.disabled = true
      this.selectedRelay = null
      this.updateDownloadButton()
      return
    }
    
    try {
      // Fetch relays for this location
      const response = await fetch(`/device_setup/relays/${locationId}`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      if (!response.ok) throw new Error('Failed to load relays')
      
      const relays = await response.json()
      
      // Clear and populate relay select
      this.relaySelectTarget.innerHTML = '<option value="">Select a relay server</option>'
      
      relays.forEach(relay => {
        const option = document.createElement('option')
        option.value = relay.id
        option.textContent = `${relay.name} (${relay.hostname}) - Load: ${relay.load}`
        option.dataset.publicKey = relay.public_key
        this.relaySelectTarget.appendChild(option)
      })
      
      this.relaySelectTarget.disabled = false
      
    } catch (error) {
      console.error('Failed to load relays:', error)
      alert('Failed to load relay servers. Please try again.')
    }
  }

  // Handle relay selection
  relayChanged(event) {
    const relayId = event.target.value
    
    if (!relayId) {
      this.selectedRelay = null
    } else {
      const selectedOption = event.target.options[event.target.selectedIndex]
      this.selectedRelay = {
        id: relayId,
        publicKey: selectedOption.dataset.publicKey,
        name: selectedOption.textContent
      }
      
      // Show server info if you have that target
      const serverInfo = document.getElementById('server-info')
      const serverDetails = document.getElementById('server-details')
      if (serverInfo && serverDetails) {
        serverDetails.textContent = `Selected: ${this.selectedRelay.name}`
        serverInfo.classList.remove('hidden')
      }
    }
    
    this.updateDownloadButton()
  }

  // Copy key to clipboard
  async copyKey(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    const key = button.dataset.key
    
    if (!key) return
    
    try {
      await navigator.clipboard.writeText(key)
      
      // Show success feedback
      const originalHTML = button.innerHTML
      button.innerHTML = '<svg class="h-5 w-5 text-green-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"></path></svg>'
      
      setTimeout(() => {
        button.innerHTML = originalHTML
      }, 2000)
      
    } catch (error) {
      console.error('Failed to copy:', error)
      alert('Failed to copy to clipboard')
    }
  }

  // Handle manual key input
  manualKeyInput() {
    this.updateDownloadButton()
  }

  // Submit form and download config
  async submitForm(event) {
    event.preventDefault()
    
    // Get the private key based on method
    let privateKey
    const keyMethod = document.querySelector('input[name="key_method"]:checked').value
    
    if (keyMethod === 'generate') {
      if (!this.currentKeys) {
        alert('Please generate keys first')
        return
      }
      privateKey = this.currentKeys.privateKey
    } else {
      privateKey = this.manualPrivateKeyTarget.value
      const publicKey = this.manualPublicKeyTarget.value
      
      if (!privateKey || !publicKey) {
        alert('Please enter both private and public keys')
        return
      }
      
      // Set the public key for submission
      this.publicKeyInputTarget.value = publicKey
    }
    
    if (!this.selectedRelay) {
      alert('Please select a relay server')
      return
    }
    
    // Create form data
    const formData = new FormData(this.formTarget)
    formData.append('private_key', privateKey)
    formData.append('relay_id', this.selectedRelay.id)
    
    try {
      // Disable submit button
      this.downloadButtonTarget.disabled = true
      this.downloadButtonTarget.textContent = 'Generating config...'
      
      const response = await fetch(this.formTarget.action, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        // Download the config file
        const blob = await response.blob()
        const url = window.URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        
        // Get filename from response headers
        const contentDisposition = response.headers.get('content-disposition')
        const filenameMatch = contentDisposition?.match(/filename="(.+)"/)
        const filename = filenameMatch ? filenameMatch[1] : 'vpn9-config.conf'
        
        a.download = filename
        document.body.appendChild(a)
        a.click()
        window.URL.revokeObjectURL(url)
        document.body.removeChild(a)
        
        // Show success message
        this.downloadButtonTarget.textContent = 'Config downloaded!'
        this.downloadButtonTarget.classList.add('bg-green-600')
        
        // Redirect after a delay
        setTimeout(() => {
          window.location.href = '/devices'
        }, 1500)
        
      } else {
        const text = await response.text()
        console.error('Server error:', text)
        alert('Failed to create device. Please try again.')
        
        // Re-enable button
        this.downloadButtonTarget.disabled = false
        this.downloadButtonTarget.textContent = 'Download WireGuard Config'
      }
      
    } catch (error) {
      console.error('Network error:', error)
      alert('Network error. Please check your connection and try again.')
      
      // Re-enable button
      this.downloadButtonTarget.disabled = false
      this.downloadButtonTarget.textContent = 'Download WireGuard Config'
    }
  }

  // Update download button state based on form completion
  updateDownloadButton() {
    if (!this.hasDownloadButtonTarget) return
    
    const keyMethod = document.querySelector('input[name="key_method"]:checked')?.value
    let hasKeys = false
    
    if (keyMethod === 'generate') {
      hasKeys = this.currentKeys !== null
    } else if (keyMethod === 'manual') {
      const privateKey = this.hasManualPrivateKeyTarget ? this.manualPrivateKeyTarget.value : ''
      const publicKey = this.hasManualPublicKeyTarget ? this.manualPublicKeyTarget.value : ''
      hasKeys = privateKey && publicKey
    }
    
    const hasRelay = this.selectedRelay !== null
    
    this.downloadButtonTarget.disabled = !(hasKeys && hasRelay)
    
    if (this.downloadButtonTarget.disabled) {
      this.downloadButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      this.downloadButtonTarget.classList.remove('hover:bg-indigo-700')
    } else {
      this.downloadButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      this.downloadButtonTarget.classList.add('hover:bg-indigo-700')
    }
  }
}