// High-converting landing page optimizations

document.addEventListener('DOMContentLoaded', function() {
  // 1. Exit Intent Popup
  let exitIntentShown = false;
  
  document.addEventListener('mouseout', function(e) {
    if (e.clientY <= 0 && !exitIntentShown && !sessionStorage.getItem('exitIntentShown')) {
      exitIntentShown = true;
      sessionStorage.setItem('exitIntentShown', 'true');
      showExitIntentOffer();
    }
  });

  // 2. Countdown Timer for Urgency
  function initCountdownTimer() {
    const timer = document.getElementById('offer-countdown');
    if (!timer) return;
    
    // Set end time to 24 hours from now (resets daily)
    let endTime = localStorage.getItem('offerEndTime');
    if (!endTime || new Date(endTime) < new Date()) {
      endTime = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
      localStorage.setItem('offerEndTime', endTime);
    }
    
    const updateTimer = () => {
      const now = new Date();
      const end = new Date(endTime);
      const diff = end - now;
      
      if (diff <= 0) {
        timer.innerHTML = 'Offer Expired';
        localStorage.removeItem('offerEndTime');
        return;
      }
      
      const hours = Math.floor(diff / (1000 * 60 * 60));
      const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
      const seconds = Math.floor((diff % (1000 * 60)) / 1000);
      
      timer.innerHTML = `
        <span class="font-bold">${hours}h ${minutes}m ${seconds}s</span> remaining
      `;
    };
    
    updateTimer();
    setInterval(updateTimer, 1000);
  }

  // 3. Live Visitor Counter (simulated but realistic)
  function initVisitorCounter() {
    const counter = document.getElementById('visitor-counter');
    if (!counter) return;
    
    // Simulate realistic visitor patterns
    let baseVisitors = 47;
    let currentVisitors = baseVisitors + Math.floor(Math.random() * 15);
    
    const updateVisitors = () => {
      // Random fluctuation
      const change = Math.random() > 0.5 ? 1 : -1;
      currentVisitors += change;
      
      // Keep within realistic bounds
      if (currentVisitors < baseVisitors - 10) currentVisitors = baseVisitors;
      if (currentVisitors > baseVisitors + 20) currentVisitors = baseVisitors + 10;
      
      counter.innerHTML = `<span class="font-bold">${currentVisitors}</span> people viewing this page`;
    };
    
    updateVisitors();
    setInterval(updateVisitors, 3000 + Math.random() * 4000);
  }

  // 4. Recent Activity Notifications
  function showActivityNotifications() {
    const activities = [
      { location: 'Berlin, Germany', action: 'just secured their privacy' },
      { location: 'Tokyo, Japan', action: 'started anonymous browsing' },
      { location: 'New York, USA', action: 'paid with Bitcoin' },
      { location: 'London, UK', action: 'created an account' },
      { location: 'Paris, France', action: 'upgraded to premium' },
      { location: 'Sydney, Australia', action: 'connected 5 devices' },
      { location: 'Toronto, Canada', action: 'chose Monero payment' },
      { location: 'Amsterdam, Netherlands', action: 'joined VPN9' }
    ];
    
    let index = 0;
    
    const showNotification = () => {
      const notification = document.createElement('div');
      notification.className = 'fixed bottom-4 left-4 bg-white rounded-lg shadow-lg p-4 flex items-center space-x-3 z-50 transform translate-x-[-100%] transition-transform duration-500';
      notification.innerHTML = `
        <div class="flex-shrink-0">
          <svg class="h-6 w-6 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>
        <div>
          <p class="text-sm font-medium text-gray-900">Someone from ${activities[index].location}</p>
          <p class="text-sm text-gray-500">${activities[index].action}</p>
        </div>
      `;
      
      document.body.appendChild(notification);
      
      // Animate in
      setTimeout(() => {
        notification.style.transform = 'translateX(0)';
      }, 100);
      
      // Animate out and remove
      setTimeout(() => {
        notification.style.transform = 'translateX(-100%)';
        setTimeout(() => {
          document.body.removeChild(notification);
        }, 500);
      }, 4000);
      
      index = (index + 1) % activities.length;
    };
    
    // Start after 5 seconds, then every 15-25 seconds
    setTimeout(() => {
      showNotification();
      setInterval(showNotification, 15000 + Math.random() * 10000);
    }, 5000);
  }

  // 5. Sticky Discount Bar
  function initStickyBar() {
    const bar = document.createElement('div');
    bar.id = 'sticky-discount-bar';
    bar.className = 'fixed top-0 left-0 right-0 bg-gradient-to-r from-indigo-600 to-purple-600 text-white py-2 px-4 text-center z-50 transform translate-y-[-100%] transition-transform duration-500';
    bar.innerHTML = `
      <p class="text-sm font-medium">
        🎉 Limited Time: Get 50% off your first month with code <span class="font-bold">PRIVACY50</span>
        <span id="offer-countdown" class="ml-2"></span>
      </p>
    `;
    
    document.body.appendChild(bar);
    
    // Show after scroll
    let scrollShown = false;
    window.addEventListener('scroll', () => {
      if (window.scrollY > 200 && !scrollShown) {
        scrollShown = true;
        bar.style.transform = 'translateY(0)';
        initCountdownTimer();
      }
    });
  }

  // 6. Trust Badge Animation
  function animateTrustBadges() {
    const badges = document.querySelectorAll('.trust-badge');
    badges.forEach((badge, index) => {
      setTimeout(() => {
        badge.classList.add('animate-pulse');
        setTimeout(() => {
          badge.classList.remove('animate-pulse');
        }, 2000);
      }, index * 200);
    });
    
    // Repeat every 10 seconds
    setInterval(() => animateTrustBadges(), 10000);
  }

  // 7. Exit Intent Offer Modal
  function showExitIntentOffer() {
    const modal = document.createElement('div');
    modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
    modal.innerHTML = `
      <div class="bg-white rounded-lg p-8 max-w-md mx-4">
        <h2 class="text-2xl font-bold text-gray-900 mb-4">Wait! Don't Leave Unprotected</h2>
        <p class="text-gray-600 mb-6">Your ISP is tracking every site you visit. Get 30% off VPN9 right now and browse anonymously.</p>
        <div class="space-y-4">
          <a href="/signup" class="block w-full text-center bg-indigo-600 text-white rounded-lg px-4 py-3 font-semibold hover:bg-indigo-700">
            Claim 30% Discount
          </a>
          <button onclick="this.closest('.fixed').remove()" class="block w-full text-center text-gray-500 hover:text-gray-700">
            No thanks, I'll stay exposed
          </button>
        </div>
      </div>
    `;
    document.body.appendChild(modal);
  }

  // Initialize all optimizations
  initStickyBar();
  initVisitorCounter();
  showActivityNotifications();
  animateTrustBadges();
});

// 8. Smart CTA Button Enhancement
document.addEventListener('DOMContentLoaded', function() {
  const ctaButtons = document.querySelectorAll('a[href="/signup"]');
  
  ctaButtons.forEach(button => {
    // Add pulsing animation to primary CTAs
    if (button.classList.contains('bg-indigo-500') || button.classList.contains('bg-indigo-600')) {
      button.classList.add('animate-pulse-slow');
    }
    
    // Track hover time for engagement
    let hoverStart;
    button.addEventListener('mouseenter', () => {
      hoverStart = Date.now();
    });
    
    button.addEventListener('mouseleave', () => {
      const hoverTime = Date.now() - hoverStart;
      if (hoverTime > 2000) {
        // User hesitated - show encouraging message
        const tooltip = document.createElement('div');
        tooltip.className = 'absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-3 py-1 bg-gray-900 text-white text-xs rounded';
        tooltip.textContent = 'No credit card required!';
        button.style.position = 'relative';
        button.appendChild(tooltip);
        
        setTimeout(() => {
          tooltip.remove();
        }, 3000);
      }
    });
  });
});