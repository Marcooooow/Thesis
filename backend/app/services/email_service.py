"""Email service abstraction for sending invitations and notifications."""

import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime
from typing import Optional


class EmailService:
    """Service for sending emails via SMTP."""

    def __init__(self):
        """Initialize email service with SMTP configuration from environment."""
        self.smtp_host = os.getenv("SMTP_HOST")
        self.smtp_port = int(os.getenv("SMTP_PORT", "587"))
        self.smtp_username = os.getenv("SMTP_USERNAME")
        self.smtp_password = os.getenv("SMTP_PASSWORD")
        self.smtp_from = os.getenv("SMTP_FROM")
        self.is_configured = all([
            self.smtp_host,
            self.smtp_port,
            self.smtp_username,
            self.smtp_password,
            self.smtp_from,
        ])

    def send_invitation_email(
        self,
        recipient_email: str,
        team_name: str,
        inviter_name: str,
        invitation_link: str,
        expires_at: datetime,
        role: str = "Employee",
    ) -> bool:
        """
        Send team invitation email to recipient.

        Args:
            recipient_email: Email address of invited user
            team_name: Name of the team
            inviter_name: Name of the manager who sent the invitation
            invitation_link: Full URL link to accept invitation
            expires_at: When the invitation expires
            role: Role being invited for (e.g., "Employee", "Manager")

        Returns:
            bool: True if email sent successfully, False otherwise
        """
        if not self.is_configured:
            print("WARNING: SMTP not configured, email not sent")
            return False

        try:
            subject = f"You're invited to join {team_name}"

            # Plain text body
            text_body = f"""Hello,

You have been invited to join the team "{team_name}" as an {role}.

Invitation Details:
- Team: {team_name}
- Invited by: {inviter_name}
- Role: {role}
- Expires: {expires_at.strftime('%Y-%m-%d %H:%M:%S %Z')}

To accept this invitation, click the link below:
{invitation_link}

If you don't have an IntelliBreak account yet, you'll be able to create one using this link.

Best regards,
IntelliBreak Team
"""

            # HTML body
            html_body = f"""
<html>
  <head></head>
  <body style="font-family: Arial, sans-serif; color: #333;">
    <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
      <h1>Team Invitation</h1>
      <p>Hello,</p>
      <p>You have been invited to join the team <strong>{team_name}</strong> as an <strong>{role}</strong>.</p>

      <div style="background-color: #f5f5f5; padding: 15px; border-radius: 5px; margin: 20px 0;">
        <p><strong>Invitation Details:</strong></p>
        <ul>
          <li><strong>Team:</strong> {team_name}</li>
          <li><strong>Invited by:</strong> {inviter_name}</li>
          <li><strong>Role:</strong> {role}</li>
          <li><strong>Expires:</strong> {expires_at.strftime('%Y-%m-%d %H:%M:%S %Z')}</li>
        </ul>
      </div>

      <p>
        <a href="{invitation_link}" style="background-color: #007BFF; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; display: inline-block;">
          Accept Invitation
        </a>
      </p>

      <p style="font-size: 12px; color: #666; margin-top: 30px;">
        If you don't have an IntelliBreak account yet, you'll be able to create one using this link.
      </p>

      <p style="font-size: 12px; color: #666;">
        Best regards,<br>
        IntelliBreak Team
      </p>
    </div>
  </body>
</html>
"""

            # Create message
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = self.smtp_from
            msg["To"] = recipient_email

            # Attach both plain text and HTML versions
            msg.attach(MIMEText(text_body, "plain"))
            msg.attach(MIMEText(html_body, "html"))

            # Send email
            with smtplib.SMTP(self.smtp_host, self.smtp_port) as server:
                server.starttls()
                server.login(self.smtp_username, self.smtp_password)
                server.send_message(msg)

            return True

        except Exception as e:
            print(f"ERROR: Failed to send invitation email: {e}")
            return False

    def send_acceptance_notification_email(
        self,
        manager_email: str,
        employee_name: str,
        team_name: str,
    ) -> bool:
        """
        Send acceptance notification email to manager.

        Args:
            manager_email: Email address of the team manager
            employee_name: Name of the employee who accepted
            team_name: Name of the team

        Returns:
            bool: True if email sent successfully, False otherwise
        """
        if not self.is_configured:
            print("WARNING: SMTP not configured, email not sent")
            return False

        try:
            subject = f"{employee_name} accepted your invitation to {team_name}"

            # Plain text body
            text_body = f"""Hello,

Good news! {employee_name} has accepted your invitation to join {team_name}.

They are now part of your team and can start collaborating.

Best regards,
IntelliBreak Team
"""

            # HTML body
            html_body = f"""
<html>
  <head></head>
  <body style="font-family: Arial, sans-serif; color: #333;">
    <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
      <h1>Invitation Accepted</h1>
      <p>Hello,</p>
      <p>Good news! <strong>{employee_name}</strong> has accepted your invitation to join <strong>{team_name}</strong>.</p>
      <p>They are now part of your team and can start collaborating.</p>
      <p style="font-size: 12px; color: #666; margin-top: 30px;">
        Best regards,<br>
        IntelliBreak Team
      </p>
    </div>
  </body>
</html>
"""

            # Create message
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = self.smtp_from
            msg["To"] = manager_email

            # Attach both plain text and HTML versions
            msg.attach(MIMEText(text_body, "plain"))
            msg.attach(MIMEText(html_body, "html"))

            # Send email
            with smtplib.SMTP(self.smtp_host, self.smtp_port) as server:
                server.starttls()
                server.login(self.smtp_username, self.smtp_password)
                server.send_message(msg)

            return True

        except Exception as e:
            print(f"ERROR: Failed to send acceptance notification email: {e}")
            return False

    def send_decline_notification_email(
        self,
        manager_email: str,
        employee_email: str,
        team_name: str,
    ) -> bool:
        """
        Send decline notification email to manager.

        Args:
            manager_email: Email address of the team manager
            employee_email: Email of the employee who declined
            team_name: Name of the team

        Returns:
            bool: True if email sent successfully, False otherwise
        """
        if not self.is_configured:
            print("WARNING: SMTP not configured, email not sent")
            return False

        try:
            subject = f"Invitation declined for {team_name}"

            # Plain text body
            text_body = f"""Hello,

Unfortunately, {employee_email} has declined your invitation to join {team_name}.

Best regards,
IntelliBreak Team
"""

            # HTML body
            html_body = f"""
<html>
  <head></head>
  <body style="font-family: Arial, sans-serif; color: #333;">
    <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
      <h1>Invitation Declined</h1>
      <p>Hello,</p>
      <p>Unfortunately, <strong>{employee_email}</strong> has declined your invitation to join <strong>{team_name}</strong>.</p>
      <p style="font-size: 12px; color: #666; margin-top: 30px;">
        Best regards,<br>
        IntelliBreak Team
      </p>
    </div>
  </body>
</html>
"""

            # Create message
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = self.smtp_from
            msg["To"] = manager_email

            # Attach both plain text and HTML versions
            msg.attach(MIMEText(text_body, "plain"))
            msg.attach(MIMEText(html_body, "html"))

            # Send email
            with smtplib.SMTP(self.smtp_host, self.smtp_port) as server:
                server.starttls()
                server.login(self.smtp_username, self.smtp_password)
                server.send_message(msg)

            return True

        except Exception as e:
            print(f"ERROR: Failed to send decline notification email: {e}")
            return False


class MockEmailService:
    """Mock email service for testing - does not send actual emails."""

    def __init__(self):
        """Initialize mock email service."""
        self.is_configured = True
        self.sent_emails = []

    def send_invitation_email(
        self,
        recipient_email: str,
        team_name: str,
        inviter_name: str,
        invitation_link: str,
        expires_at: datetime,
        role: str = "Employee",
    ) -> bool:
        """Mock method - logs email instead of sending."""
        self.sent_emails.append({
            "type": "invitation",
            "to": recipient_email,
            "team": team_name,
            "inviter": inviter_name,
            "link": invitation_link,
        })
        return True

    def send_acceptance_notification_email(
        self,
        manager_email: str,
        employee_name: str,
        team_name: str,
    ) -> bool:
        """Mock method - logs email instead of sending."""
        self.sent_emails.append({
            "type": "acceptance",
            "to": manager_email,
            "employee": employee_name,
            "team": team_name,
        })
        return True

    def send_decline_notification_email(
        self,
        manager_email: str,
        employee_email: str,
        team_name: str,
    ) -> bool:
        """Mock method - logs email instead of sending."""
        self.sent_emails.append({
            "type": "decline",
            "to": manager_email,
            "employee": employee_email,
            "team": team_name,
        })
        return True
