# Connect Google Calendar

Sotto can read Google calendars directly without adding the account to macOS Internet Accounts. The connection uses Google Calendar API read-only calendar-list and event scopes. Event lists are fetched as needed for upcoming meetings and automation; Sotto does not keep a separate event database. A recording may retain the calendar context captured when it starts.

1. Enable the Google Calendar API in your Google Cloud project.
2. In Sotto, open Settings → Meeting Recording and choose Connect Google Calendar. If Google Drive is already configured, Sotto reuses its OAuth client configuration. Otherwise, configure the OAuth consent screen, create a Desktop app OAuth client, and import its downloaded JSON under Google Calendar. For an app in testing, add your Google account as a test user.
3. Complete Google sign-in in the browser and approve the requested Calendar access.
4. Enable the calendar reminder or auto-start option and select the calendars to include.

Sotto stores Calendar client configuration and tokens in a dedicated Keychain entry. Reusing the Drive client does not copy Drive tokens. Disconnect removes those local credentials; remove the app's access in Google account settings if you also want to revoke the Google grant. Google may apply additional consent, verification, or testing restrictions to the Cloud project.

If Sotto cannot read the saved Drive client, import the downloaded Desktop OAuth client JSON directly under Google Calendar. This leaves the existing Drive credentials untouched.

If a new build cannot access saved Calendar credentials, choose **Allow Keychain access** in Calendar settings and approve the macOS prompts for the existing items. The credentials remain in Keychain; ad-hoc signed builds may require approval again after an update.
