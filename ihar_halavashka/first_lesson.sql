-- 1. Display the number of films in each category, sorted in descending order.

with film_counter_per_category as (
	select 
	  c.name as category_name, 
	  count(f.film_id) as number_of_films
	from film f
	join film_category fc on f.film_id = fc.film_id
	join category c on c.category_id = fc.category_id
	group by c.name
)

select category_name, number_of_films
from film_counter_per_category
order by number_of_films desc;


-- 2. Display the top 10 actors whose films were rented the most, sorted in descending order.

with actors_and_most_rented_films as (
	select 
	  a.actor_id,
	  a.first_name,
	  a.last_name,
	  count(r.rental_id) as rent_count,
	  rank() over(order by count(r.rental_id) desc) rnk
	from actor a
	join film_actor fa on a.actor_id = fa.actor_id
	join film f on fa.film_id = f.film_id
	join inventory i on f.film_id = i.film_id
	join rental r on i.inventory_id = r.inventory_id
	group by a.actor_id, a.first_name, a.last_name
)

select 
	actor_id,
	first_name,
	last_name,
	rent_count
from actors_and_most_rented_films
where rnk <= 10
order by rent_count desc;


-- 3. Display the category of films that generated the highest revenue.

with revenue_by_category as (
	select
		c.name,
		sum(p.amount) as revenue,
		rank() over( order by sum(p.amount) desc) rnk
	from category c 
	join film_category fc on c.category_id = fc.category_id
	join film f on fc.film_id = f.film_id
	join inventory i on f.film_id = i.film_id
	join rental r on i.inventory_id = r.inventory_id
	join payment p on r.rental_id = p.rental_id
	group by c.name
)

select
	rc.name,
	rc.revenue,
	rc.rnk
from revenue_by_category rc
order by rc.revenue desc;


-- 4. Display the titles of films not present in the inventory. Write the query without using the IN operator.

-- With IN operator:
select 
	title
from film
where film_id not in (
	select 
		film_id
	from inventory
);

-- Without IN operator
select 
	f.title
from film f 
left join inventory i on f.film_id = i.film_id
where i.inventory_id is null;


-- 5. Display the top 3 actors 
-- who appeared the most in films within the "Children" category. 
-- If multiple actors have the same count, include all.

with actor_film_count as (
	select 
		a.first_name,
		a.last_name,
		count(*) as film_count,
		rank() over(order by count(*) desc) rnk
	from actor a 
	join film_actor fa on a.actor_id = fa.actor_id
	join film_category fc on fa.film_id = fc.film_id
	join category c on fc.category_id = c.category_id
	where c.name = 'Children'
	group by 
		a.first_name,
		a.last_name
	order by film_count desc
)

select *
from actor_film_count afc
where afc.rnk <= 3;

-- 6. Display cities with the count of active and inactive customers (active = 1).
-- Sort by the count of inactive customers in descending order.


with active_inactive_customer as (
	select 
		ci.city,
		count(case when cu.active = 1 then 1 end) as active_customer,
		count(case when cu.active <> 1 then 0 end) as inactive_customer
	from city ci
	join address a on ci.city_id = a.city_id
	join customer cu on a.address_id = cu.address_id
	group by ci.city
)


select * 
from active_inactive_customer
order by inactive_customer desc;


--  7.Display the film category with the highest total rental hours in cities
--   where customer.address_id belongs to that city and starts with the letter "a".
--   Do the same for cities containing the symbol "-". Write this in a single query.



select city_name, film_category, rental_hours
from( 
	select
		ci.city as city_name,
		ca.name as film_category,
		round(sum(extract(epoch from (re.return_date - re.rental_date))/3600), 2) as rental_hours,
		rank() over(partition by ci.city order by sum(extract(epoch from (re.return_date - re.rental_date))/3600) desc) as rnk
	from rental re
	join customer cu on re.customer_id = cu.customer_id
	join address ad on cu.address_id = ad.address_id
	join city ci on ad.city_id = ci.city_id
	join inventory inv on re.inventory_id = inv.inventory_id
	join film fi on inv.film_id = fi.film_id
	join film_category fc on fi.film_id = fc.film_id
	join category ca on fc.category_id = ca.category_id
	where ci.city like 'a%' or ci.city like '%-%'
	group by ci.city, ca.name
)
where rnk = 1;
