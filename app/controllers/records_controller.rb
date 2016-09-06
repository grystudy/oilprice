class RecordsController < ApplicationController
	def index
		@records = Record.order(updated_at: :desc)
	end

	def destroy
		@record = Record.find(params[:id])
		@record.destroy
		redirect_to records_path, notice: "已撤销变更"
	end

	def push_diff
		revision = Revision.last
		if revision
			data = Record.where(revision_id: revision.id,uploaded: false)
			if data.length == 0
				redirect_to records_path,notice: "发布失败,无新数据!"
				return
			else
				if params[:execute]
					if async_upload_records data
						new_revision = Revision.create({name: "after push diff"})
						new_revision.user = current_user
						new_revision.save!
						message = "全部数据上传成功!"		
					else
						message = "某些数据上传失败，请重新尝试!"
					end
					redirect_to push_diff_records_path,notice: message
					return			
				else
					@commit = true
					@records = data
					render 'index'
					return					
				end
			end
		else
			redirect_to records_path,notice: "无版本"
			return
		end
	end

	def push_all
		revision = Revision.last
		if revision
			relation = Record.select("max(revision_id) as last_version,oiltype_id").group("oiltype_id")
			data = []
			relation.each do |variable|
				rec_ = Record.where(oiltype_id: variable.oiltype_id,revision_id: variable.last_version)
				if rec_.length == 1
					data << rec_.first
				end
			end
			if data.length == 0
				message = "发布失败,无新数据!"
			else
				data = Record.where(revision_id: revision.id)
				if data.length == 0
					message = "发布成功但不需要创建新版本。"
				else
					if async_upload_records data
						new_revision = Revision.create({name: "after push all"})
						new_revision.user = current_user
						new_revision.save!
						message = "发布成功并且创建新版本。"
					else
						message = "上传数据失败。"
					end
				end
			end
		else
			message = "无版本"
		end

		redirect_to records_path,notice: message
	end

	def stash
		revision = Revision.last
		if revision
			data = Record.where(revision_id: revision.id)
			if data.length == 0
				message = "创建失败,无新数据!"
			else
				new_revision = Revision.create({name: "after stash"})
				new_revision.user = current_user
				new_revision.save!
				message = "成功"
			end
		else
			message = "无版本"
		end

		redirect_to records_path,notice: message
	end

	private	
	require 'net/http'
	base_uri = "192.168.5.57"
	port = 3000
	sub_url = "api/v1/oilprice/modifyOilPrice"

	def upload_record record_
		Net::HTTP.version_1_2
		begin
			res =Net::HTTP.start(base_uri, port) {|http|
				response = http.get("#{sub_url}?apikey=mxnavi&code=#{record_.region.code}&area=#{record_.region.name}&standard=#{record_.standard.name}&number=#{record_.oiltype.name}&price=#{record_.value}&updatetime=#{record_.local_updated_at}")
				response.body}
			return res
		rescue Exception => e
			return false 
		end
	end

	def async_upload_records records_
		res = true
		return res if !records_ || records_.length == 0
		max_thread_count = 5
		index = 0
		while index < records_.length
			left = records_.length - index
			min = left > max_thread_count ? max_thread_count : left
			arr = []
			min.times do |i|
				rec = records_[index]
				index = index + 1
   			arr[i] = Thread.new { Thread.current["rec"] = rec; upload_record rec}
			end
			arr.each do |t| 
				t.join;
				if t.value
					rec =	t["rec"]
					rec.uploaded = true
					rec.save!
				else
					res = false
				end
			end
		end
		return res
	end
end
