#include <security/pam_modules.h>
#include <security/pam_ext.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <time.h>
#include <curl/curl.h>

//Define the global variables
#define API_TOKEN "{api_token}"
#define API_BASE_URL "{site_url}/sapi/"
#define USER_SESSION_KEY "USER_SESSION_CODE"

// Function to generate a unique code (you can customize this)
char* generate_unique_code(const char* username) {
  // Seed the random number generator
    srand(time(NULL));

    // Define the characters that can be used in the code
    const char charset[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

    const int code_length = 10; // Adjust the length as needed

    char* unique_code = (char*)malloc((code_length + 1) * sizeof(char));

    if (unique_code != NULL) {
        // Generate the code
        for (int i = 0; i < code_length; i++) {
            int index = rand() % (sizeof(charset) - 1);
            unique_code[i] = charset[index];
        }
        unique_code[code_length] = '\0'; // Null-terminate the string
    }

    return unique_code;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {

    const char *username;
    pam_get_user(pamh, &username, NULL);
    
    const char *user_ip;
    pam_get_item(pamh, PAM_RHOST, (const void **)&user_ip);

    // Skip API call for the 'root' user
    if (strcmp(username, "root") == 0) {
        return PAM_SUCCESS;
    }

    // Generate and store a unique code for this user
    char *session_key = generate_unique_code(username);
    // Store the unique code, e.g., in an environment variable
    setenv(USER_SESSION_KEY, session_key, 1);

    CURL *curl = curl_easy_init();
    if (!curl) {
        syslog(LOG_ERR, "Failed to initialize libcurl");
        return PAM_AUTH_ERR;
    }

    char api_url[256]; // Adjust the buffer size as needed
    snprintf(api_url, sizeof(api_url), "%sulogin?token=%s&username=%s&session_key=%s&user_ip=%s", API_BASE_URL, API_TOKEN, username, session_key, user_ip);
    
    syslog(LOG_ERR, "API: %s", api_url);

    curl_easy_setopt(curl, CURLOPT_URL, api_url);

    CURLcode res = curl_easy_perform(curl);

    if (res == CURLE_OK) {
        long http_code = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);

        syslog(LOG_ERR, "HTTP Response Code: %ld", http_code);

        syslog(LOG_ERR, "Custom authenticate username:%s session key:%s", username, session_key);

        if (http_code == 200) {
            curl_easy_cleanup(curl);
            return PAM_SUCCESS;
        }
        
    } 
    
    syslog( LOG_ERR, "API call for user '%s' failed: %s", username, curl_easy_strerror(res));
    curl_easy_cleanup(curl);
    return PAM_AUTH_ERR;

}

PAM_EXTERN int pam_sm_open_session(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    
    const char *username;
    pam_get_user(pamh, &username, NULL);
    

    // Retrieve the unique code from the environment
    const char *session_key = getenv(USER_SESSION_KEY);

    // Log the unique code
    if (session_key != NULL) {
        syslog(LOG_ERR, "Unique Code on open session_key: %s & username %s", session_key , username);
    }

    syslog(LOG_ERR, "Custom open session username:%s session key:%s", username, session_key);

    return PAM_SUCCESS;
}

PAM_EXTERN int pam_sm_close_session(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    const char *username;
    pam_get_user(pamh, &username, NULL);

     // Skip API call for the 'root' user
    if (strcmp(username, "root") == 0) {
        return PAM_SUCCESS;
    }

    const char *user_ip;
    pam_get_item(pamh, PAM_RHOST, (const void **)&user_ip);

    // Retrieve the unique code from the environment
    const char *session_key = getenv(USER_SESSION_KEY);
    
    CURL *curl = curl_easy_init();
    if (!curl) {
        syslog(LOG_ERR, "Failed to initialize libcurl");
        return PAM_SUCCESS;
    }

    syslog(LOG_ERR, "Custom close session username:%s session key:%s", username, session_key);

    char api_url[256]; // Adjust the buffer size as needed
    snprintf(api_url, sizeof(api_url), "%sulogout?token=%s&username=%s&session_key=%s&user_ip=%s", API_BASE_URL, API_TOKEN, username, session_key, user_ip);
    
    curl_easy_setopt(curl, CURLOPT_URL, api_url);

    CURLcode res = curl_easy_perform(curl);

    if (res != CURLE_OK) {
        syslog(LOG_ERR, "API call for user '%s' on logout failed: %s", username, curl_easy_strerror(res));
    }

    curl_easy_cleanup(curl);
    return PAM_SUCCESS;
}
