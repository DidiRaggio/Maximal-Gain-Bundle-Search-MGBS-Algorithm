
require 'matrix'
require 'pp'
require 'benchmark'


mp = [
	[90,95,98,0,88],
	[30,0,35,39,0],
	[0,48,50,58,45],
	[80,0,0,75,0]
]


class Array

  def delete_at_multi(arr)
    arr = arr.sort.reverse # delete highest indexes first.
    arr.each do |i|
      self.delete_at i
    end
    self
  end

end

class MGBS

	def initialize
		@DataHash = { aux_matrixes: {}, min_bundles: {}, initial_bundles: {}}
	end

	def bundle_search_algorithm(matrix)
		init_mp(matrix)
		@DataHash[:mp].column_vectors.each_with_index do |seller_bundle, idx|
			seller_sv =  Array.new(@DataHash[:mp_num_rows], idx)
			seller_costs, seller_sums, seller_discounts = single_bundle_cost(@DataHash[:mp_num_cols], seller_bundle, seller_sv)
			@DataHash[:initial_bundles].merge!(idx =>{
				"bundle": seller_bundle,
				"sv": seller_sv,
				"seller_sums": seller_sums, 
				"total_sum": sum_elements(seller_sums),
				"seller_discounts": seller_discounts,
				"total_discount": sum_elements(seller_discounts), 
				"seller_costs": seller_costs,
				"bundle_cost": sum_elements(seller_costs) 
			})
		end

		calc_max_sub_cost()
		calc_gains()
		find_min_bundle()
	end

	def init_mp(mp)
		mp0 = Matrix.rows(mp)
		cols = mp0.column_vectors
		non_empty = []
		cols.each {|col| non_empty << col if col.any?  {|e| e != 0} }
		mp = Matrix.columns(non_empty)
		# mp = Matrix.rows(mp)
		@DataHash.merge!({"mp": mp, "mp_num_rows": mp.row_count, "mp_num_cols": mp.column_count})
		calc_p_min_and_sv_min()
		create_mr()
		repeated_mr_columns()
	end

	def create_mr
		mr = @DataHash[:mp].clone.to_a
		@DataHash[:mp].each_with_index do |e, row, col|
			if e != 0
				mr[row][col] = 1
			end
		end
		@DataHash.merge!({"mr": Matrix.rows(mr)})
	end


	def repeated_mr_columns
		mr = @DataHash[:mr]
		repeated_mr_columns = []
		mr_columns = mr.column_vectors
		(0...mr_columns.length).each do |idx|
			if idx == 0
				repeated_mr_columns << idx
			else
				(0...idx).each do |jdx|
					if mr_columns[idx] == mr_columns[jdx]
						repeated_mr_columns << jdx
						break
					elsif idx-1 == jdx
						repeated_mr_columns << idx
					end
				end
			end
		end

		@DataHash.merge!({"repeated_mr_columns": repeated_mr_columns})
	end

	#DETERMINE Pmin and SVmin 2
	def calc_p_min_and_sv_min()
		p_min = []
		sv_min = []
		@DataHash[:mp].each_with_index do |e, row, col|
			if e > 0 && 
				if p_min[row].nil?
					p_min[row] = e
				elsif e < p_min[row]
					p_min[row] = e
				end
				sv_min[row] = col 
			end
		end
		@DataHash.merge!({"p_min": p_min, "sv_min": sv_min})
	end

	def get_rows_to_remove(col)
		base_column = @DataHash[:mp].column(col).to_a
		rows_to_remove = base_column.each_index.select{|i| base_column[i] == 0}
		return rows_to_remove
	end

	def inverse_removed_rows(removed_rows)
		return [*0...@DataHash[:mp_num_rows]] - removed_rows
	end


	def auxiliary_matrix(rows_to_remove)
		aux_matrix = @DataHash[:mp].clone
		aux_arrays = aux_matrix.row_vectors.map(&:to_a) 
		aux_arrays.delete_at_multi(rows_to_remove)
		return Matrix.rows(aux_arrays)
	end


	#SUM OF MIN PRICES
	def sum_elements(vector)
		vector.inject(0){|sum,x| sum + x }
	end

	def calc_discount(seller_sum, idx)
		discount = 0
		case 
		when seller_sum < 50
			discount_ = 0
		when seller_sum.between?(50, 100)
			discount = 10
		when seller_sum.between?(100, 150)
			discount = 20
		when seller_sum.between?(150, 199)
			discount = 35
		when seller_sum >= 200
			discount = (seller_sum*0.2).to_i
		end
		return discount
	end


	def seller_sums(matrix)
		seller_sums = []
		matrix.column_vectors.each_with_index do |col, idx|
			seller_sums << sum_elements(col)
		end
		return Vector.elements(seller_sums)
	end




	# def bundle_costs(matrix)
	# 	return (seller_sums(matrix) - calc_matrix_discounts(matrix))
	# end





	def single_bundle_cost(m, bundle, sv)

		discount_vector = []
		seller_sums = Array.new(m, 0)
		bundle.each_with_index do |value, idx|
			seller_sums[sv[idx]] += value
		end
		seller_sums.each_with_index do |seller_sum, jdx|
			discount_vector << calc_discount(seller_sum, jdx)
		end
		bundle_vector = Vector.elements(seller_sums)
		discount_vector = Vector.elements(discount_vector)
		seller_costs = bundle_vector - discount_vector
		return  seller_costs, bundle_vector, discount_vector 
	end


	def calc_max_sub_cost

		@DataHash.merge!("new_bundle_costs_per_seller": [],"new_bundle_costs": [], "new_bundle_costs_svs": [],"new_bundle_costs_discounts": [], "removed_rows": [], "new_bundle_seller_sums": [])
		repeated_mr_columns = @DataHash[:repeated_mr_columns]
		repeated_mr_columns.uniq.each_with_index do |col, idx|
			removed_rows = get_rows_to_remove(col)
			aux_matrix = auxiliary_matrix(removed_rows)
			bundles_hash = find_all_bundles(aux_matrix)
			@DataHash[:aux_matrixes].merge!(idx => bundles_hash)
			@DataHash[:removed_rows] << removed_rows
		end
		
		

		@DataHash[:aux_matrixes].each do |aux_matrix|
			aux_matrix[1][:bundles].each_with_index do |bundle, idx|
				# bundle, seller_sum, discount
				seller_costs, seller_sums, seller_discounts = single_bundle_cost(@DataHash[:mp_num_cols], bundle[1][:bundle], bundle[1][:sv])
				@DataHash[:aux_matrixes][aux_matrix[0]][:bundles][idx].merge!({
					"bundle": bundle[1][:bundle],
					"sv": bundle[1][:sv],
					"seller_sums": seller_sums, 
					"total_sum": sum_elements(seller_sums),
					"seller_discounts": seller_discounts,
					"total_discount": sum_elements(seller_discounts), 
					"seller_costs": seller_costs,
					"bundle_cost": sum_elements(seller_costs) 
					})
			end
		end

		
		initial_bundle_costs = []
		@DataHash[:initial_bundles].each { |bundle| initial_bundle_costs << bundle[1][:bundle_cost]}
		@DataHash.merge!({"initial_bundle_costs": initial_bundle_costs})


		@DataHash[:initial_bundle_costs].each_with_index do |bundle_cost, idx|
		# initial_bundle_costs.each_with_index do |bundle_cost, idx|
			returned_values = @DataHash[:aux_matrixes][repeated_mr_columns[idx]][:bundles].find_all {|bundle| bundle[1][:bundle_cost] < bundle_cost}
			returned_value = returned_values.sort_by {|d| d[1][:bundle_cost]}.first
			if returned_value.nil?
				returned_values = @DataHash[:aux_matrixes][repeated_mr_columns[idx]][:bundles].find_all {|bundle| bundle[1][:bundle_cost] > bundle_cost}
				returned_value = returned_values.sort_by {|d| d[1][:bundle_cost]}.first
				@DataHash[:new_bundle_costs] << returned_value[1][:bundle_cost] 
				@DataHash[:new_bundle_costs_svs] << returned_value[1][:sv]
				@DataHash[:new_bundle_costs_per_seller] << returned_value[1][:seller_costs] 
				@DataHash[:new_bundle_seller_sums] << returned_value[1][:seller_sums]
				@DataHash[:new_bundle_costs_discounts] << returned_value[1][:total_discount] 
			else
				@DataHash[:new_bundle_costs] << returned_value[1][:bundle_cost]
				@DataHash[:new_bundle_costs_svs] << returned_value[1][:sv]
				@DataHash[:new_bundle_costs_discounts] << returned_value[1][:total_discount]
				@DataHash[:new_bundle_costs_per_seller] << returned_value[1][:seller_costs]
				@DataHash[:new_bundle_seller_sums] << returned_value[1][:seller_sums]
			end
		end
	end

	def array_element_to_element_division(array1, array2)
		array1.each_with_index.map { |x,i| x/array2[i].to_f }
	end

	def vector_element_to_element_division(vector1, vector2)
		# array1.each_with_index.map { |x,i| [x/array2[i].to_f] }
		Vector.elements(vector1.each_with_index.map { |x,i| x/vector2[i].to_f })
	end


	def calc_gains()


		new_bundle_costs =	Vector.elements(@DataHash[:new_bundle_costs])
		bundle_costs_svs = @DataHash[:new_bundle_costs_svs]
		new_bundle_costs_discounts = @DataHash[:new_bundle_costs_discounts]
		removed_rows_per_bundle_cost = @DataHash[:removed_rows]
		old_bundle_costs = Vector.elements(@DataHash[:initial_bundle_costs])
		new_bundle_costs_per_seller = @DataHash[:new_bundle_costs_per_seller]
		new_bundle_seller_sums = @DataHash[:new_bundle_seller_sums]
		old_bundles = []
		old_bundle_costs_per_seller = []
		old_bundle_costs_svs = []
		old_bundle_seller_sums = []
		@DataHash[:initial_bundles].each_with_index do |bundle, idx| 
			old_bundles << bundle[1][:bundle]
			old_bundle_costs_svs << bundle[1][:sv]
			old_bundle_costs_per_seller << bundle[1][:seller_costs]
			old_bundle_seller_sums << bundle[1][:seller_sums]
		end

		final_bundles = []
		absolute_gains = []
		final_bundle_costs = []
		final_bundle_costs_per_seller = []
		final_bundle_seller_sums = []
		relative_gains = array_element_to_element_division((new_bundle_costs - old_bundle_costs),  new_bundle_costs)

		relative_gains.each_with_index.map do |x,i|
			empty_rows = removed_rows_per_bundle_cost[@DataHash[:repeated_mr_columns][i] ]
			discount = new_bundle_costs_discounts[i]
			if discount == 0
				discount = 1
			end
			absolute_gain = x*discount/((empty_rows.size+1).to_f)
		
			if absolute_gain > 0
				final_bundles[i] = old_bundle_costs[i]
				 new_array_svs = Array.new(@DataHash[:mp_num_rows], i)
				 empty_rows.each { |row| new_array_svs.pop()}
				 bundle_costs_svs[i] = new_array_svs
				 new_array_cost = Array.new(@DataHash[:mp_num_cols], 0)
				 new_array_cost[i] = old_bundle_costs[i]
				 final_bundle_costs_per_seller << new_array_cost
				 final_bundle_seller_sums << old_bundle_seller_sums[i]
			else
				final_bundles[i] = new_bundle_costs[i]
				final_bundle_costs_per_seller << new_bundle_costs_per_seller[i]
				final_bundle_seller_sums << new_bundle_seller_sums[i]
			end
		
			absolute_gains << absolute_gain
		end

		@DataHash.merge!({"absolute_gains": absolute_gains, "final_bundles": Vector.elements(final_bundles), "final_bundles_svs": bundle_costs_svs, "final_bundle_costs_per_seller": final_bundle_costs_per_seller, "final_bundle_seller_sums": final_bundle_seller_sums})

	end

	def missing_rows(repeated_mr_columns, removed_rows_per_bundle_cost)
		rows_array = []
		repeated_mr_columns.each do |value|
			rows_array << removed_rows_per_bundle_cost[value]
		end
		return rows_array
	end




	def find_all_bundles(matrix)

		m = matrix.column_count
		n = matrix.row_count

		prev_iter_sv = []
		current_iter_sv = []
		iter_accumilator_sv = []

		prev_iter = []
		current_iter = []
		iter_accumilator = []

		row = 0
		while row < n
			(0...m).each do |col|
				if matrix[row, col] > 0
					if prev_iter.size < 2
						current_iter_sv << col
						current_iter << matrix[row, col]
						iter_accumilator_sv << current_iter_sv
						iter_accumilator << current_iter
					else
						prev_iter.each_with_index do |bundle, idx|
							prevous_sv = prev_iter_sv[idx].clone
							prevous_bundle = bundle.clone
							prevous_sv << col
							prevous_bundle << matrix[row, col]
							current_iter_sv << prevous_sv
							current_iter << prevous_bundle
						end
						iter_accumilator_sv += current_iter_sv
						iter_accumilator += current_iter
					end
					current_iter_sv = []
					current_iter = []
				end
			end
			prev_iter_sv = iter_accumilator_sv
			prev_iter = iter_accumilator
			iter_accumilator_sv = []
			iter_accumilator = []
			row += 1
		end

		bundles_hash = {bundles: {}}
		prev_iter.each_with_index { |k,v| bundles_hash[:bundles][v] ={:bundle => k}}
		prev_iter_sv.each_with_index {|k,v| bundles_hash[:bundles][v].merge!(:sv => k)}

		return bundles_hash
	end



	def find_min_bundle()
		absolute_gains = @DataHash[:absolute_gains]
		final_bundles_svs = @DataHash[:final_bundles_svs]
		final_bundle_costs_per_seller = @DataHash[:final_bundle_costs_per_seller]
		final_bundle_seller_sums = @DataHash[:final_bundle_seller_sums]


		removed_rows = @DataHash[:removed_rows]
		repeated_mr_columns = @DataHash[:repeated_mr_columns]

		max_gain_id = absolute_gains.index(absolute_gains.max)

		aux_matrix= auxiliary_matrix(
			inverse_removed_rows(
				removed_rows[repeated_mr_columns[max_gain_id]]
				)
			)

		bundles_hash = find_all_bundles(aux_matrix)

		@DataHash[:min_bundles].merge!(0 => bundles_hash)

		@DataHash[:min_bundles][0][:bundles].each_with_index do |bundle, idx|
				seller_costs, seller_sums, seller_discounts = single_bundle_cost(@DataHash[:mp_num_cols], bundle[1][:bundle], bundle[1][:sv])
				@DataHash[:min_bundles][0][:bundles][idx].merge!({
					"bundle": bundle[1][:bundle],
					"sv": bundle[1][:sv],
					"seller_sums": seller_sums, 
					"total_sum": sum_elements(seller_sums),
					"seller_discounts": seller_discounts,
					"total_discount": sum_elements(seller_discounts), 
					"seller_costs": seller_costs,
					"bundle_cost": sum_elements(seller_costs) 
					})
		end
		
		resulting_bundle_costs = []
		@DataHash[:min_bundles][0][:bundles].each do |bundle|
			seller_sums = bundle[1][:seller_sums] + final_bundle_seller_sums[max_gain_id]
			discount_vector = []
			seller_sums.each_with_index do |seller_sum, pdx|
				discount_vector << calc_discount(seller_sum, pdx)
			end
			resulting_bundle_costs << sum_elements(seller_sums - Vector.elements(discount_vector))
		end
		optimal_min_bundle_id =  resulting_bundle_costs.rindex(resulting_bundle_costs.min)
		optimal_bundle_sv = final_bundles_svs[max_gain_id].clone
		removed_rows[max_gain_id].each_with_index do |row, idx|
			optimal_bundle_sv.insert(row, @DataHash[:min_bundles][0][:bundles][optimal_min_bundle_id][:sv][idx])
		end

		return optimal_bundle_sv, resulting_bundle_costs.min
	end






	def process_cart(cart)
		puts "THIS IS THE CART #{cart.inspect}"
	end


end









mgbs = MGBS.new()


# puts ''
# puts mgbs.calc_gains(mp)
# puts mgbs.instance_variable_get(:@DataHash)#[:p_min]


# puts ""
# puts ""
# puts ""
# puts mgbs.find_min_bundle()

puts mgbs.bundle_search_algorithm(mp).inspect
# puts mgbs.instance_variable_get(:@DataHash)#[:p_min]

# puts Benchmark.measure {mgbs.bundle_search_algorithm(mp)}

# Benchmark.bm do |bm|
#   # joining an array of strings
#   bm.report do
#     4000.times do
#       mgbs.bundle_search_algorithm(mp)
#     end
#   end
# end

# 0]], :repeated_mr_columns=>[0, 1, 2, 3, 1], :new_bundle_costs_per_seller=>[Vector[100, 0, 0, 65, 0], Vector[0, 0, 0, 0, 113], Vector[100, 0, 40, 0, 0], Vector[90, 0, 40, 0, 0], Vector[0, 0, 40, 0, 78]], :new_bundle_costs=>[165, 113, 140, 130, 118], :new_bundle_costs_svs=>[[0, 0, 0], [4, 4], [0, 0, 2], [0, 2, 0], [4, 4]], :new_bundle_costs_discounts=>[30, 20, 30, 30, 20], :removed_rows=>[[2], [1, 3], [3], [0]], :new_bundle_seller_sums=>[Vector[120, 0, 0, 75, 0], Vector[0, 0, 0, 0, 133], Vector[120, 0, 50, 0, 0], Vector[110, 0, 50, 0, 0], Vector[0, 0, 50, 0, 88]], :initial_bundle_costs=>[160, 123, 148, 137, 113], :absolute_gains=>[0.9090909090909092, -0.8849557522123894, -1.7142857142857142, -1.6153846153846154, 0.423728813559322], :final_bundles=>Vector[160, 113, 140, 130, 113], :final_bundles_svs=>[[0, 0, 0], [4, 4], [0, 0, 2], [0, 2, 0], [4, 4]], :final_bundle_costs_per_seller=>[[160, 0, 0, 0, 0], Vector[0, 0, 0, 0, 113], Vector[100, 0, 40, 0, 0], Vector[90, 0, 40, 0, 0], [0, 0, 0, 0, 113]], :final_bundle_seller_sums=>[Vector[200, 0, 0, 0, 0], Vector[0, 0, 0, 0, 133], Vector[120, 0, 50, 0, 0], Vector[110, 0, 50, 0, 0], Vector[0, 0, 0, 0, 133]]}
