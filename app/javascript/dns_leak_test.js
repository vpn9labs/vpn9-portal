// DNS Leak Test functionality
document.addEventListener('DOMContentLoaded', function() {
  const startDnsTestBtn = document.getElementById('start-dns-test');
  const restartDnsTestBtn = document.getElementById('restart-dns-test');
  const dnsTestInitial = document.getElementById('dns-test-initial');
  const dnsTestRunning = document.getElementById('dns-test-running');
  const dnsTestResults = document.getElementById('dns-test-results');
  const dnsResultsContent = document.getElementById('dns-results-content');
  const progressBar = document.getElementById('progress-bar');
  
  let currentTestId = null;
  
  if (startDnsTestBtn) {
    startDnsTestBtn.addEventListener('click', runDnsLeakTest);
  }
  
  if (restartDnsTestBtn) {
    restartDnsTestBtn.addEventListener('click', function() {
      resetDnsTest();
      runDnsLeakTest();
    });
  }
  
  function runDnsLeakTest() {
    // Show running state
    dnsTestInitial.classList.add('hidden');
    dnsTestResults.classList.add('hidden');
    dnsTestRunning.classList.remove('hidden');
    
    // Start progress bar animation
    let progress = 0;
    const progressInterval = setInterval(() => {
      progress += Math.random() * 15;
      if (progress >= 90) {
        progress = 90;
        clearInterval(progressInterval);
      }
      progressBar.style.width = progress + '%';
    }, 300);
    
    // Start the DNS leak test
    fetch('/api/v1/dns_leak_test', {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      currentTestId = data.test_id;
      
      // Trigger DNS queries by creating hidden images with the test domains
      data.domains.forEach((domain, index) => {
        setTimeout(() => {
          const img = new Image();
          img.src = 'https://' + domain + '/pixel.gif?' + Date.now();
          img.style.display = 'none';
          document.body.appendChild(img);
          
          // Clean up after a short delay
          setTimeout(() => {
            if (document.body.contains(img)) {
              document.body.removeChild(img);
            }
          }, 1000);
        }, index * 200);
      });
      
      // Wait for DNS propagation, then get results
      setTimeout(() => {
        getDnsTestResults(currentTestId);
      }, 3000);
    })
    .catch(error => {
      console.error('DNS test error:', error);
      showDnsTestError('Failed to start DNS leak test. Please try again.');
    });
  }
  
  function getDnsTestResults(testId) {
    fetch('/api/v1/dns_leak_test/results?test_id=' + testId, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      // Complete progress bar
      progressBar.style.width = '100%';
      
      setTimeout(() => {
        showDnsTestResults(data);
      }, 500);
    })
    .catch(error => {
      console.error('DNS results error:', error);
      showDnsTestError('Failed to get DNS test results. Please try again.');
    });
  }
  
  function showDnsTestResults(data) {
    dnsTestRunning.classList.add('hidden');
    
    const isSecure = !data.leak_detected;
    const statusColor = isSecure ? 'green' : 'red';
    const statusIcon = isSecure ? 
      '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />' :
      '<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />';
    
    let dnsServersHtml = '';
    if (data.dns_servers && data.dns_servers.length > 0) {
      dnsServersHtml = '<div class="mt-4"><h5 class="font-semibold text-gray-900 mb-2">Detected DNS Servers:</h5><ul class="space-y-1">';
      data.dns_servers.forEach(server => {
        const serverColor = server.is_isp_server ? 'text-red-600' : 'text-green-600';
        dnsServersHtml += `<li class="text-sm ${serverColor}">• ${server.ip} - ${server.provider} (${server.location})</li>`;
      });
      dnsServersHtml += '</ul></div>';
    }
    
    let recommendationsHtml = '';
    if (data.recommendations && data.recommendations.length > 0) {
      recommendationsHtml = '<div class="mt-4"><h5 class="font-semibold text-gray-900 mb-2">Recommendations:</h5><ul class="space-y-1">';
      data.recommendations.forEach(rec => {
        recommendationsHtml += `<li class="text-sm text-gray-600">• ${rec}</li>`;
      });
      recommendationsHtml += '</ul></div>';
    }
    
    dnsResultsContent.innerHTML = `
      <div class="text-center mb-4">
        <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-lg bg-${statusColor}-600 mx-auto">
          <svg class="h-8 w-8 text-white" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            ${statusIcon}
          </svg>
        </div>
        <h3 class="text-xl font-semibold text-gray-900 mb-2">
          ${isSecure ? 'No DNS Leaks Detected' : 'DNS Leak Detected!'}
        </h3>
        <p class="text-${statusColor}-600 font-medium mb-4">${data.analysis}</p>
      </div>
      ${dnsServersHtml}
      ${recommendationsHtml}
    `;
    
    dnsTestResults.classList.remove('hidden');
  }
  
  function showDnsTestError(message) {
    dnsTestRunning.classList.add('hidden');
    dnsResultsContent.innerHTML = `
      <div class="text-center">
        <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-lg bg-red-600 mx-auto">
          <svg class="h-8 w-8 text-white" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
          </svg>
        </div>
        <h3 class="text-xl font-semibold text-gray-900 mb-2">Test Error</h3>
        <p class="text-red-600">${message}</p>
      </div>
    `;
    dnsTestResults.classList.remove('hidden');
  }
  
  function resetDnsTest() {
    dnsTestResults.classList.add('hidden');
    dnsTestRunning.classList.add('hidden');
    dnsTestInitial.classList.remove('hidden');
    progressBar.style.width = '0%';
    currentTestId = null;
  }
});