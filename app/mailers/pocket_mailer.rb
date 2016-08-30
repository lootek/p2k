class PocketMailer < ActionMailer::Base
	default from: Settings.DELIVERY_EMAIL_ADDRESS

	def delivery_email(delivery, files, articles)
		@delivery = delivery
		email_subject = "Your " + @delivery.frequency.titleize + " Delivery From P2K"

		@articles_info = ''
		articles.each do |article|
			@articles_info = @articles_info + "\n\n" +
					article['resolved_title'] + "\n" +
					article['resolved_url'] + "\n" +
					DateTime.strptime(article['time_added'], '%s').strftime('%Y-%m-%d_%H-%M-%S') + "\n" +
					article['resolved_id']
		end

		files.each do |file|
			begin
				attachments[file] = {mime_type: 'application/x-mobipocket-ebook', content: File.read(file)}
			rescue => e
				Rails.logger.debug "Attaching file failed: " + e.message
			end

		end

		Rails.logger.debug "Sending to " + @delivery.kindle_email + ", " + email_subject + "!\n"
		mail(to: @delivery.kindle_email, subject: email_subject)

		Rails.logger.debug "EMAIL SENT! to " + @delivery.kindle_email + " via SMTP"
		logger.debug "EMAIL SENT! to " + @delivery.kindle_email + " via SMTP"
	end
end
