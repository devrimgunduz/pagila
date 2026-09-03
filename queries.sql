-- 1 Output the number of movies in each category, sorted in descending order.

SELECT 
    c.name,
    COUNT(f.film_id) as film_count
FROM film f 
JOIN film_category fc ON fc.film_id = f.film_id
JOIN category c on fc.category_id = c.category_id
GROUP BY c.name
ORDER BY film_count DESC;

-- 2 Output the 10 actors whose movies rented the most, sorted in descending order.

SELECT 
    a.first_name,
    a.last_name,
    COUNT(r.inventory_id) as rent_count
FROM actor a 
JOIN film_actor fa ON a.actor_id = fa.actor_id
JOIN film f ON f.film_id = fa.film_id
JOIN inventory i ON i.film_id = f.film_id
JOIN rental r ON r.inventory_id = i.inventory_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY rent_count DESC
LIMIT 10;

-- 3 Output the category of movies on which the most money was spent.

SELECT 
    c.name,
    SUM(p.amount) as total_amount
FROM category c
JOIN film_category fc ON fc.category_id = c.category_id
JOIN film f ON f.film_id = fc.film_id
JOIN inventory i on i.film_id = f.film_id
JOIN rental r ON r.inventory_id = i.inventory_id
JOIN payment p on p.rental_id = r.rental_id
GROUP BY c.name
ORDER BY total_amount DESC
LIMIT 1;

-- 4 Output the names of movies that are not in the inventory.

SELECT 
    f.title
FROM film f
WHERE NOT EXISTS (
    SELECT 1
    FROM inventory i
    WHERE i.film_id = f.film_id
);

-- 5 Output the top 3 actors who have appeared most in movies in the "Children" category.
-- If several actors have the same number of movies, output all of them.

WITH actor_count AS (
    SELECT 
        a.first_name,
        a.last_name,
        COUNT(DISTINCT f.film_id) as appearing_count
    FROM actor a
    JOIN film_actor fa ON a.actor_id = fa.actor_id
    JOIN film f ON f.film_id = fa.film_id
    JOIN film_category fc ON fc.film_id = f.film_id
    JOIN category c ON c.category_id = fc.category_id
    WHERE c.name = 'Children'
    GROUP BY a.actor_id, a.first_name, a.last_name
)
SELECT 
    first_name, last_name, appearing_count
FROM actor_count
WHERE appearing_count >= (
    SELECT appearing_count 
    FROM actor_count
    ORDER BY appearing_count DESC
    OFFSET 2
    LIMIT 1
)
ORDER BY appearing_count DESC;

-- 6 Output cities with the number of active and inactive customers (active - customer.active = 1).
-- Sort by the number of inactive customers in descending order.

SELECT
    c.city,
    SUM(cust.active) as active_users,
    COUNT(cust.customer_id) - SUM(cust.active) as inactive_users
FROM city c
JOIN address a ON c.city_id = a.city_id
JOIN customer cust ON cust.address_id = a.address_id
GROUP BY c.city_id, c.city
ORDER BY inactive_users DESC; 

-- 7 Output the category of movies that have the highest number of total rental hours
-- in the cities (customer.address_id in this city), and that start with the letter "a".
-- Do the same for cities with a "-" symbol.

-- Cities starting with "a"
WITH city_category_hours AS (
    SELECT
        c.city_id,
        c.city,
        cat.name AS category,
        SUM(f.length) / 60.0 AS total_rental_hours
    FROM city c
    JOIN address addr ON addr.city_id = c.city_id
    JOIN customer cust ON cust.address_id = addr.address_id
    JOIN rental r ON r.customer_id = cust.customer_id
    JOIN inventory i ON i.inventory_id = r.inventory_id
    JOIN film f ON f.film_id = i.film_id
    JOIN film_category fc ON fc.film_id = f.film_id
    JOIN category cat ON cat.category_id = fc.category_id
    WHERE c.city ILIKE 'a%'
    GROUP BY c.city_id, c.city, cat.category_id, cat.name
),
ranked AS (
    SELECT
        city,
        category,
        total_rental_hours,
        ROW_NUMBER() OVER (
            PARTITION BY city_id
            ORDER BY total_rental_hours DESC, category
        ) AS rn
    FROM city_category_hours
)
SELECT
    city,
    category,
    ROUND(total_rental_hours::numeric, 2) AS total_rental_hours
FROM ranked
WHERE rn = 1
ORDER BY city;

-- Cities with "-" in the name
WITH city_category_hours AS (
    SELECT
        c.city_id,
        c.city,
        cat.name AS category,
        SUM(f.length) / 60.0 AS total_rental_hours
    FROM city c
    JOIN address addr ON addr.city_id = c.city_id
    JOIN customer cust ON cust.address_id = addr.address_id
    JOIN rental r ON r.customer_id = cust.customer_id
    JOIN inventory i ON i.inventory_id = r.inventory_id
    JOIN film f ON f.film_id = i.film_id
    JOIN film_category fc ON fc.film_id = f.film_id
    JOIN category cat ON cat.category_id = fc.category_id
    WHERE c.city LIKE '%-%'
    GROUP BY c.city_id, c.city, cat.category_id, cat.name
),
ranked AS (
    SELECT
        city,
        category,
        total_rental_hours,
        ROW_NUMBER() OVER (
            PARTITION BY city_id
            ORDER BY total_rental_hours DESC, category
        ) AS rn
    FROM city_category_hours
)
SELECT
    city,
    category,
    ROUND(total_rental_hours::numeric, 2) AS total_rental_hours
FROM ranked
WHERE rn = 1
ORDER BY city;


