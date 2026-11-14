# Connect Google Calendar

Sotto can read Google calendars directly without adding the account to macOS Internet Accounts. The connection uses Google Calendar API read-only calendar-list and event scopes. Event lists are fetched as needed for upcoming meetings and automation; Sotto does not keep a separate event database. A recording may retain the calendar context captured when it starts.

1. In Google Cloud, create or select a project and enable the Google Calendar API.
2. Configure the OAuth consent screen and, if the app is in testing, add your Google account as a test user.
3. Create an OAuth client of type Desktop app and download its JSON file.
4. In Sotto, open Settings → Meeting Recording, import the JSON under Google Calendar, and choose Connect Google Calendar. Complete Google sign-in in the browser.
5. Enable the calendar reminder or auto-start option and select the calendars to include.

Sotto stores the client configuration and tokens in a dedicated Keychain entry. Disconnect removes those local credentials; remove the app's access in Google account settings if you also want to revoke the Google grant. Google may apply additional consent, verification, or testing restrictions to the Cloud project.
