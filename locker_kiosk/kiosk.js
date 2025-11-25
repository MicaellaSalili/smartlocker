// API Configuration
const API_BASE_URL = 'http://localhost:3000/api';

// Store transaction data globally
let currentTransaction = null;

// OTP Timer
let otpTimer = null;
let otpTimeRemaining = 300; // 5 minutes in seconds

function showPage(pageId) {
  document.querySelectorAll(".page").forEach((page) => {
    page.classList.remove("active");
  });
  document.getElementById(pageId).classList.add("active");
}

function selectCourier() {
  // Navigate to QR generator page
  window.location.href = "qr-generator.html";
}

function selectRecipient() {
  showPage("pickupPage");
  // Clear previous data
  currentTransaction = null;
  document.getElementById("trackingCode").value = "";
}

function goBack() {
  showPage("homePage");
  // Clear data when going back
  stopOTPTimer();
  currentTransaction = null;
  document.getElementById("trackingCode").value = "";
  clearOTPInputs();
}

function goBackFromOTP() {
  stopOTPTimer();
  showPage("pickupPage");
  clearOTPInputs();
}

function isAlphaNumeric(e) {
        var code = ('charCode' in e) ? e.charCode : e.keyCode;
        // Regex for valid characters (alphabets and numbers)
        var regex = /^[a-zA-Z0-9]+$/;
        var isValid = regex.test(String.fromCharCode(code));
        if (!isValid) {
            e.preventDefault(); // Prevent the character from being entered
        }
        return isValid;
      }

function isNumeric(e) {
        var code = ('charCode' in e) ? e.charCode : e.keyCode;
        // Regex for valid characters (numbers)
        var regex = /^-?\d+(\.\d+)?$/;
        var isValid = regex.test(String.fromCharCode(code));
        if (!isValid) {
            e.preventDefault(); // Prevent the character from being entered
        }
        return isValid;
      }

function clearOTPInputs() {
  for (let i = 1; i <= 6; i++) {
    const input = document.getElementById(`otp${i}`);
    if (input) {
      input.value = "";
      input.classList.remove("filled");
    }
  }
}

// Modal Functions
function showModal(modalId) {
  const modal = document.getElementById(modalId);
  if (modal) {
    modal.classList.add('active');
  }
}

function hideModal(modalId) {
  const modal = document.getElementById(modalId);
  if (modal) {
    modal.classList.remove('active');
  }
}

function showErrorModal(title, message) {
  document.getElementById('errorTitle').textContent = title;
  document.getElementById('errorMessage').textContent = message;
  showModal('errorModal');
}

function closeErrorModal() {
  hideModal('errorModal');
}

function closeOTPSentModal() {
  hideModal('otpSentModal');
}

function showWarningModal(title, message) {
  document.getElementById('warningTitle').textContent = title;
  document.getElementById('warningMessage').textContent = message;
  showModal('warningModal');
}

function closeWarningModal() {
  hideModal('warningModal');
}

function updateLockerDisplay(lockerId) {
  // Update all locker number displays
  const openingLocker = document.getElementById('openingLockerNumber');
  const successLocker = document.getElementById('successLockerNumber');
  const successInstruction = document.getElementById('successInstruction1');
  
  if (openingLocker) {
    openingLocker.textContent = `Locker #${lockerId}`;
  }
  if (successLocker) {
    successLocker.textContent = lockerId;
  }
  if (successInstruction) {
    successInstruction.textContent = `Retrieve your parcel from locker #${lockerId}`;
  }
}

// OTP Timer Functions
function startOTPTimer() {
  // Reset timer
  otpTimeRemaining = 300; // 5 minutes
  updateTimerDisplay();
  
  // Clear any existing timer
  if (otpTimer) {
    clearInterval(otpTimer);
  }
  
  // Start countdown
  otpTimer = setInterval(() => {
    otpTimeRemaining--;
    updateTimerDisplay();
    
    if (otpTimeRemaining <= 0) {
      clearInterval(otpTimer);
      handleOTPExpired();
    }
  }, 1000);
}

function updateTimerDisplay() {
  const minutes = Math.floor(otpTimeRemaining / 60);
  const seconds = otpTimeRemaining % 60;
  const timerElement = document.getElementById('otpTimer');
  const timerContainer = document.querySelector('.timer-container');
  
  if (timerElement) {
    timerElement.textContent = `${minutes}:${seconds.toString().padStart(2, '0')}`;
  }
  
  // Change color when time is running out (< 1 minute)
  if (timerContainer) {
    if (otpTimeRemaining < 60) {
      timerContainer.classList.add('expired');
    } else {
      timerContainer.classList.remove('expired');
    }
  }
}

function stopOTPTimer() {
  if (otpTimer) {
    clearInterval(otpTimer);
    otpTimer = null;
  }
}

function handleOTPExpired() {
  stopOTPTimer();
  showErrorModal('OTP Expired', 'Your OTP has expired. Please request a new one.');
  setTimeout(() => {
    hideModal('errorModal');
    showPage('pickupPage');
    clearOTPInputs();
  }, 3000);
}

async function verifyCode() {
  const code = document.getElementById("trackingCode").value.trim();
  
  if (code === "") {
    showErrorModal('Invalid Input', 'Please enter a tracking code');
    return;
  }

  try {
    // Show loading state
    const button = event.target;
    const originalText = button.textContent;
    button.textContent = "Verifying...";
    button.disabled = true;

    // Call backend API to verify waybill and generate OTP
    const response = await fetch(`${API_BASE_URL}/claim/verify-tracking`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ waybill_id: code })
    });

    const data = await response.json();

    // Restore button state
    button.textContent = originalText;
    button.disabled = false;

    if (!response.ok) {
      // Handle errors with modal
      if (response.status === 404) {
        showErrorModal('Not Found', 'Tracking number not found in database. Please check and try again.');
      } else if (response.status === 400) {
        if (data.error && data.error.includes('already been claimed')) {
          showWarningModal('Already Claimed', 'This parcel has already been claimed and cannot be retrieved again.');
        } else {
          showErrorModal('Invalid Request', data.error || 'This parcel is invalid or unavailable.');
        }
      } else {
        showErrorModal('Error', data.error || 'Failed to verify tracking number. Please try again.');
      }
      return;
    }

    // Success - store transaction data including locker_id
    currentTransaction = {
      transaction_id: data.transaction_id,
      waybill_id: data.waybill_id,
      recipient_name: data.recipient_name,
      phone_masked: data.phone_masked,
      locker_id: data.locker_id // Store locker ID from database
    };

    // Clear OTP inputs before showing page
    clearOTPInputs();

    // Update locker display with the locker_id from database
    if (data.locker_id) {
      updateLockerDisplay(data.locker_id);
    }

    // Update phone number display
    const phoneElement = document.getElementById('recipientPhone');
    if (phoneElement) {
      phoneElement.textContent = data.phone_masked;
    }

    // Show OTP sent modal (no alert popup)
    const modalMessage = document.getElementById('otpSentMessage');
    if (modalMessage) {
      modalMessage.innerHTML = `A 6-digit OTP has been generated for:<br><strong>${data.recipient_name}</strong><br><br>Check the server console for your OTP code.`;
    }
    showModal('otpSentModal');
    
    // When modal is closed, move to OTP page and start timer
    setTimeout(() => {
      // Move to OTP verification page
      showPage("otpPage");
      // Start the 5-minute timer
      startOTPTimer();
    }, 100);

  } catch (error) {
    console.error("Error verifying tracking code:", error);
    
    // Restore button state
    const button = event.target;
    button.textContent = "Continue";
    button.disabled = false;
    
    showErrorModal('Connection Error', 'Cannot connect to server. Please check if the server is running and try again.');
  }
}

function moveToNext(current, nextId) {
  if (current.value.length === 1) {
    current.classList.add("filled");
    if (nextId) {
      document.getElementById(nextId).focus();
    }
  }
}

function moveToPrev(event, current, prevId) {
  if (event.key === "Backspace" && current.value === "" && prevId) {
    const prevInput = document.getElementById(prevId);
    prevInput.focus();
    prevInput.value = "";
    prevInput.classList.remove("filled");
  }
}

function handleLastInput(current) {
  if (current.value.length === 1) {
    current.classList.add("filled");
  }
}

async function verifyOTP() {
  const otp =
    document.getElementById("otp1").value +
    document.getElementById("otp2").value +
    document.getElementById("otp3").value +
    document.getElementById("otp4").value +
    document.getElementById("otp5").value +
    document.getElementById("otp6").value;

  if (otp.length !== 6) {
    showErrorModal('Incomplete OTP', 'Please enter all 6 digits');
    return;
  }

  if (!currentTransaction) {
    showErrorModal('Session Expired', 'Your session has expired. Please start over.');
    setTimeout(() => {
      hideModal('errorModal');
      showPage("homePage");
    }, 2000);
    return;
  }

  try {
    // Show loading state
    const button = event.target;
    const originalText = button.textContent;
    button.textContent = "Verifying...";
    button.disabled = true;

    // Call backend API to verify OTP
    const response = await fetch(`${API_BASE_URL}/transaction/${currentTransaction.transaction_id}/verify-otp`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ otp: otp })
    });

    const data = await response.json();

    if (!response.ok) {
      // Restore button state
      button.textContent = originalText;
      button.disabled = false;

      // Handle errors with modal
      if (response.status === 400) {
        if (data.error.includes("expired")) {
          stopOTPTimer();
          showErrorModal('OTP Expired', 'Your OTP has expired. Please request a new one.');
          setTimeout(() => {
            hideModal('errorModal');
            showPage("pickupPage");
            clearOTPInputs();
          }, 2500);
        } else if (data.error.includes("Invalid OTP")) {
          showErrorModal('Invalid OTP', 'The OTP you entered is incorrect. Please check and try again.');
          clearOTPInputs();
        } else if (data.error.includes("No OTP requested")) {
          showErrorModal('No OTP', 'No OTP was requested for this parcel. Please start over.');
          setTimeout(() => {
            hideModal('errorModal');
            showPage("pickupPage");
          }, 2500);
        } else {
          showErrorModal('Verification Failed', data.error || 'Failed to verify OTP. Please try again.');
        }
      } else if (response.status === 404) {
        showErrorModal('Not Found', 'Transaction not found in database. Please start over.');
        setTimeout(() => {
          hideModal('errorModal');
          showPage("homePage");
          stopOTPTimer();
        }, 2500);
      } else {
        showErrorModal('Error', data.error || 'Failed to verify OTP. Please try again.');
      }
      return;
    }

    // Success - Stop timer and show verified modal
    stopOTPTimer();
    
    // Update locker display with the locker_id from database
    const lockerId = data.locker_id || currentTransaction.locker_id || '4';
    updateLockerDisplay(lockerId);
    
    // Show OTP Verified modal
    showModal('otpVerifiedModal');
    
    // Wait 2 seconds then proceed to opening page
    setTimeout(async () => {
      hideModal('otpVerifiedModal');
      
      // Navigate to opening locker page
      showPage("openingPage");

      try {
        // 🔓 STEP 1: Call API to unlock the locker via MQTT
        console.log(`🔓 Sending UNLOCK command to locker ${data.locker_id}...`);
        const unlockResponse = await fetch(`${API_BASE_URL}/locker/${data.locker_id}/unlock-claim`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          }
        });

        if (!unlockResponse.ok) {
          console.error("❌ Failed to unlock locker");
        } else {
          console.log(`✅ Unlock command sent to ${data.locker_id}`);
        }

        // 🕐 STEP 2: Wait 5 seconds for user to retrieve parcel
        console.log(`⏳ Locker ${data.locker_id} will auto-lock in 5 seconds...`);
        
        setTimeout(async () => {
          try {
            // 🔒 STEP 3: Send LOCK command to ESP32 via MQTT
            console.log(`🔒 Sending LOCK command to locker ${data.locker_id}...`);
            const lockResponse = await fetch(`${API_BASE_URL}/locker/${data.locker_id}/lock`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
              }
            });

            if (!lockResponse.ok) {
              console.error("❌ Failed to lock locker");
            } else {
              console.log(`✅ Lock command sent to ${data.locker_id}`);
            }

            // 🎉 STEP 4: Finalize the transaction (mark as CLAIMED)
            await fetch(`${API_BASE_URL}/transaction/${currentTransaction.transaction_id}/finalize`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
              }
            });

            // Show success page
            showPage("successPage");

            // Auto return to home after 5 seconds
            setTimeout(() => {
              showPage("homePage");
              currentTransaction = null;
              document.getElementById("trackingCode").value = "";
              clearOTPInputs();
            }, 5000);

          } catch (error) {
            console.error("Error locking locker or finalizing transaction:", error);
            // Still show success page even if lock/finalize fails
            showPage("successPage");
          }
        }, 5000); // 5 seconds delay before locking

      } catch (error) {
        console.error("Error unlocking locker:", error);
        // Continue to success page anyway
        setTimeout(() => {
          showPage("successPage");
        }, 3000);
      }
    }, 2000);

  } catch (error) {
    console.error("Error verifying OTP:", error);
    
    // Restore button state
    const button = event.target;
    button.textContent = "Verify & Open Locker";
    button.disabled = false;
    
    showErrorModal('Connection Error', 'Cannot connect to server. Please check if the server is running and try again.');
  }
}

async function resendCode() {
  if (!currentTransaction) {
    showErrorModal('Session Expired', 'Your session has expired. Please start over.');
    setTimeout(() => {
      hideModal('errorModal');
      showPage("homePage");
    }, 2000);
    return;
  }

  try {
    // Call API to request new OTP
    const response = await fetch(`${API_BASE_URL}/transaction/${currentTransaction.transaction_id}/request-otp`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      }
    });

    const data = await response.json();

    if (!response.ok) {
      showErrorModal('Resend Failed', data.error || 'Failed to resend OTP. Please try again.');
      return;
    }

    // Clear inputs and restart timer
    clearOTPInputs();
    startOTPTimer();
    
    // Show success modal
    const modalMessage = document.getElementById('otpSentMessage');
    if (modalMessage) {
      modalMessage.innerHTML = `A new 6-digit OTP has been generated.<br><br>Check the server console for your new OTP code.`;
    }
    showModal('otpSentModal');

  } catch (error) {
    console.error("Error resending OTP:", error);
    showErrorModal('Connection Error', 'Cannot connect to server. Please check if the server is running and try again.');
  }
}

function goBackToHome() {
  stopOTPTimer();
  showPage("homePage");
  currentTransaction = null;
  document.getElementById("trackingCode").value = "";
  clearOTPInputs();
}

function goBackToHome() {
  showPage("homePage");
}
